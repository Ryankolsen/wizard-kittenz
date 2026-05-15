extends GutTest

# Tests for RoomClearWatcher — the per-room enemy-count watcher that
# fires DungeonRunController.mark_room_cleared on the last expected
# death. Bridges RoomSpawnPlanner.enemy_ids_for_room (what to expect)
# and DungeonRunController.mark_room_cleared (what to fire).

# --- helpers ---------------------------------------------------------------

func _make_standard_room(room_id: int, kind: int = EnemyData.EnemyKind.SLIME) -> Room:
	var r := Room.make(room_id, Room.TYPE_STANDARD)
	r.enemy_kind = kind
	return r

func _make_boss_room(room_id: int, kind: int = EnemyData.EnemyKind.RAT) -> Room:
	var r := Room.make(room_id, Room.TYPE_BOSS)
	r.enemy_kind = kind
	return r

func _make_powerup_room(room_id: int, type: String = "catnip") -> Room:
	var r := Room.make(room_id, Room.TYPE_POWERUP)
	r.power_up_type = type
	return r

func _make_start_room(room_id: int) -> Room:
	return Room.make(room_id, Room.TYPE_START)

func _make_dungeon_with(room: Room) -> Dungeon:
	# Minimal dungeon containing just the supplied room (and a separate
	# start if needed). Keeps the controller happy without dragging in a
	# full graph for every per-room test.
	var d := Dungeon.new()
	if room.type == Room.TYPE_START:
		d.add_room(room)
		d.start_id = room.id
	else:
		var s := Room.make(0, Room.TYPE_START) if room.id != 0 else Room.make(99, Room.TYPE_START)
		s.connections = [room.id]
		d.add_room(s)
		d.add_room(room)
		d.start_id = s.id
	# Boss id only needed for the dungeon_completed signal path; default
	# to room.id when room is boss type, otherwise leave as the boss-or-
	# nothing default the controller expects.
	if room.type == Room.TYPE_BOSS:
		d.boss_id = room.id
	else:
		d.boss_id = -1
	return d

func _make_controller_for(room: Room) -> DungeonRunController:
	var d := _make_dungeon_with(room)
	var c := DungeonRunController.new()
	c.start(d)
	return c

# --- watch -----------------------------------------------------------------

func test_watch_standard_room_initializes_expected_count():
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	assert_true(w.watch(room, controller))
	assert_eq(w.room_id, 3)
	assert_eq(w.initial_count(), 1, "one enemy per combat room today")
	assert_eq(w.remaining_count(), 1, "no deaths yet")
	assert_false(w.is_cleared())

func test_watch_boss_room_initializes_expected_count():
	var room := _make_boss_room(7)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	assert_true(w.watch(room, controller))
	assert_eq(w.initial_count(), 1)
	assert_false(w.is_cleared(), "boss room defaults uncleared")

func test_watch_powerup_room_auto_clears():
	# Power-up rooms have no enemies. The watcher fires
	# mark_room_cleared immediately on watch() so the player can
	# advance without a kill.
	var room := _make_powerup_room(2)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	assert_true(w.watch(room, controller))
	assert_eq(w.initial_count(), 0, "power-up rooms expect zero kills")
	assert_true(w.is_cleared(), "auto-cleared on watch")
	# Controller's auto-clear rule (enemy_kind == -1) already returns
	# true; locking that mark_room_cleared was actually called keeps
	# the explicit-cleared flag set so caller code that polls
	# _cleared (vs is_room_cleared) sees the same answer.
	assert_true(controller.is_room_cleared(room.id))

func test_watch_start_room_auto_clears():
	var room := _make_start_room(0)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	assert_true(w.watch(room, controller))
	assert_true(w.is_cleared())

func test_watch_null_room_rejected():
	var controller := DungeonRunController.new()
	var w := RoomClearWatcher.new()
	assert_false(w.watch(null, controller), "null room rejected")

func test_watch_null_controller_rejected():
	var w := RoomClearWatcher.new()
	assert_false(w.watch(_make_standard_room(1), null), "null controller rejected")

func test_watch_resets_prior_state():
	# Re-using a watcher instance across rooms (e.g. an object pool)
	# must drop the previous room's expected set and _cleared flag.
	var room_a := _make_standard_room(1)
	var controller := _make_controller_for(room_a)
	var w := RoomClearWatcher.new()
	w.watch(room_a, controller)
	w.notify_death("r1_e0")
	assert_true(w.is_cleared(), "first room cleared")

	var room_b := _make_standard_room(2)
	var controller_b := _make_controller_for(room_b)
	w.watch(room_b, controller_b)
	assert_eq(w.room_id, 2, "room_id rebound")
	assert_eq(w.remaining_count(), 1, "expected set reset")
	assert_false(w.is_cleared(), "_cleared flag reset")

# --- notify_death ----------------------------------------------------------

func test_notify_death_clears_room_on_only_enemy():
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	assert_true(w.notify_death("r3_e0"), "rising-edge clear returns true")
	assert_true(w.is_cleared())
	assert_eq(w.remaining_count(), 0)
	assert_true(controller.is_room_cleared(3))

func test_notify_death_unknown_id_no_clear():
	# Defensive against a remote enemy-died packet for an enemy in a
	# different room. The expected set is the gate.
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	assert_false(w.notify_death("r999_e0"), "unknown id rejected")
	assert_false(w.is_cleared())
	assert_eq(w.remaining_count(), 1, "expected set unchanged")
	assert_false(controller.is_room_cleared(3))

func test_notify_death_empty_id_safe_no_op():
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	assert_false(w.notify_death(""), "empty id rejected")
	assert_false(w.is_cleared())
	assert_eq(w.remaining_count(), 1)

func test_notify_death_after_cleared_safe_no_op():
	# Idempotent: a duplicate notify after the room fired is a safe
	# no-op. Same shape as DungeonRunController.mark_room_cleared and
	# EnemyStateSyncManager.apply_death.
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	w.notify_death("r3_e0")
	assert_false(w.notify_death("r3_e0"), "second notify is a no-op")
	assert_true(w.is_cleared())

func test_notify_death_twice_same_id_safe():
	# A re-broadcast of the death event (host -> remote race) shouldn't
	# affect the remaining set on the second call.
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	assert_true(w.notify_death("r3_e0"))
	# The id is gone from _expected; second call falls into the
	# "unknown id" branch and returns false safely.
	assert_false(w.notify_death("r3_e0"))

func test_notify_death_before_watch_safe():
	# Defensive: a notify before watch() (logic error from the future
	# spawner) shouldn't crash. Returns false because the expected
	# set is empty AND _cleared is false (so the empty-id / unknown-id
	# path triggers, not the cleared path).
	var w := RoomClearWatcher.new()
	assert_false(w.notify_death("r1_e0"))

func test_notify_death_does_not_double_fire_mark_room_cleared():
	# The controller's mark_room_cleared signal fires at-most-once per
	# room. The watcher relies on that, but locks its own _cleared
	# flag too so a hypothetical signal-suppression behavior change
	# wouldn't slip through.
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	watch_signals(controller)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	w.notify_death("r3_e0")
	w.notify_death("r3_e0")  # duplicate
	assert_signal_emit_count(controller, "room_cleared", 1, "single rising-edge fire")

# --- end-to-end: planner + watcher + controller ----------------------------

func test_planner_spawned_id_matches_watcher_expected_id():
	# Locks the contract that RoomSpawnPlanner and RoomClearWatcher
	# agree on the id format — the spawner mints "r3_e0" via plan_enemy
	# and the watcher expects "r3_e0" via enemy_ids_for_room. If either
	# side drifts, the watcher's notify_death(planned_id) test below
	# would fail.
	var room := _make_standard_room(3)
	var planned := RoomSpawnPlanner.plan_enemy(room)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(room)
	assert_eq(ids.size(), 1)
	assert_eq(ids[0], planned.enemy_id)

func test_end_to_end_planned_kill_clears_room():
	# Spawn an enemy via the planner, watch the room, fire notify_death
	# with the planner's minted id — controller should fire
	# room_cleared once on the rising edge.
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	watch_signals(controller)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	var planned := RoomSpawnPlanner.plan_enemy(room)
	assert_true(w.notify_death(planned.enemy_id))
	assert_signal_emit_count(controller, "room_cleared", 1)
	assert_true(controller.is_room_cleared(3))

func test_end_to_end_boss_room_fires_dungeon_completed():
	# Boss kill via the planner -> watcher -> controller pipeline.
	# DungeonRunController emits dungeon_completed on the boss-room
	# cleared edge, so the future scene's dungeon-completion handler
	# can subscribe to a single signal and not have to special-case
	# the boss room itself.
	var room := _make_boss_room(2)
	var controller := _make_controller_for(room)
	watch_signals(controller)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	var planned := RoomSpawnPlanner.plan_enemy(room)
	w.notify_death(planned.enemy_id)
	assert_signal_emit_count(controller, "dungeon_completed", 1, "boss-cleared edge fires once")

# --- PRD #52 room-clear XP -------------------------------------------------

func _make_character(level: int = 1) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	c.level = level
	return c

func _make_coop_lobby(specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in specs:
		ls.add_player(LobbyPlayer.make(spec[0], spec[1], spec[2], false))
	return ls

func _make_two_room_dungeon() -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	d.add_room(start)
	d.start_id = 0
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.RAT
	d.add_room(boss)
	d.boss_id = 1
	return d

func test_room_clear_solo_awards_xp_on_final_death():
	# AC: RoomClearWatcher awards ROOM_CLEAR_XP on the final enemy death
	# (solo path).
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var c := _make_character(1)
	var xp_before := c.xp
	var w := RoomClearWatcher.new()
	w.watch(room, controller, c)
	assert_eq(c.xp, xp_before, "no XP before death")
	w.notify_death("r3_e0")
	assert_eq(c.xp - xp_before, RoomClearWatcher.ROOM_CLEAR_XP,
		"final death awards ROOM_CLEAR_XP to solo character")

func test_room_clear_solo_no_award_without_character():
	# Test / pre-spawn-layer path: omitting the character argument leaves
	# the watcher's edge tracking intact but pays no XP.
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	assert_true(w.notify_death("r3_e0"), "edge still fires")
	# No character was passed; nothing to mutate. Pin no crash.

func test_room_clear_powerup_room_does_not_award():
	# Auto-clear (no enemies) does NOT pay out — reward fires from
	# combat, not traversal.
	var room := _make_powerup_room(2)
	var controller := _make_controller_for(room)
	var c := _make_character(1)
	var xp_before := c.xp
	var w := RoomClearWatcher.new()
	w.watch(room, controller, c)
	assert_true(w.is_cleared(), "auto-cleared")
	assert_eq(c.xp, xp_before, "auto-clear pays no XP")

func test_room_clear_idempotent_no_double_award():
	# A duplicate notify after the room fired must not pay out twice.
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var c := _make_character(1)
	var w := RoomClearWatcher.new()
	w.watch(room, controller, c)
	w.notify_death("r3_e0")
	var xp_after_first := c.xp
	w.notify_death("r3_e0")  # duplicate
	assert_eq(c.xp, xp_after_first, "no double award on duplicate notify")

func test_room_clear_coop_splits_xp_across_party():
	# AC: room clear XP splits by party size in co-op. 2-player party
	# → each gets floor(50/2) = 25.
	var lobby := _make_coop_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c, "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	var w := RoomClearWatcher.new()
	w.watch(room, controller, c, session)
	w.notify_death("r3_e0")
	assert_eq(emissions.size(), 2, "broadcaster fired for both members")
	for e in emissions:
		assert_eq(e[1], 25, "floor(50/2) per member")
	assert_eq(c.xp, 25, "local member real_stats received per-player share")

func test_room_clear_coop_single_player_keeps_full_xp():
	# 1-player co-op session: full ROOM_CLEAR_XP, no split.
	var lobby := _make_coop_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller, c, session)
	w.notify_death("r3_e0")
	assert_eq(c.xp, RoomClearWatcher.ROOM_CLEAR_XP, "1-player coop keeps full reward")

func test_end_to_end_powerup_room_auto_advance_path():
	# Power-up rooms auto-clear on watch() so the player can step
	# through. Controller's is_room_cleared returns true (via the
	# enemy_kind == -1 auto-clear rule); the watcher's mark_room_cleared
	# call doesn't need to actually flip a controller state for these.
	var room := _make_powerup_room(2)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller)
	assert_true(w.is_cleared())
	assert_true(controller.is_room_cleared(2))
