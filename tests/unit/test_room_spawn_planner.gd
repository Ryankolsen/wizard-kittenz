extends GutTest

# Tests for RoomSpawnPlanner — the data-side bridge between Dungeon graph
# Rooms and the spawn-time wiring that KillRewardRouter / EnemyStateSyncManager
# expect (populated EnemyData with stable enemy_id + is_boss).

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

func _make_session_with_lobby() -> CoopSession:
	# Non-empty party so start() can succeed; we only need enemy_sync to
	# exist after start. Single-player lobby + character map.
	var lobby := LobbyState.new()
	lobby.room_code = "ABCDE"
	var p := LobbyPlayer.make("p1", "Whiskers", "Mage", true)
	lobby.add_player(p)
	var c := CharacterFactory.create_default("Mage")
	var characters := {"p1": c}
	var s := CoopSession.new(lobby, characters)
	# Build a tiny dungeon so start() succeeds and enemy_sync is non-null.
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.RAT
	start.connections = [1]
	d.add_room(start)
	d.add_room(boss)
	d.start_id = 0
	d.boss_id = 1
	s.start(d)
	return s

# --- plan_enemy ------------------------------------------------------------

func test_plan_enemy_standard_room_returns_populated_data():
	var r := _make_standard_room(3, EnemyData.EnemyKind.SLIME)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_not_null(d)
	assert_eq(d.kind, EnemyData.EnemyKind.SLIME)
	assert_eq(d.enemy_id, "r3_e0", "id format is r{room_id}_e{spawn_idx}")
	assert_false(d.is_boss, "standard room is not a boss room")

func test_plan_enemy_boss_room_sets_is_boss():
	var r := _make_boss_room(7, EnemyData.EnemyKind.RAT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_not_null(d)
	assert_eq(d.kind, EnemyData.EnemyKind.RAT)
	assert_eq(d.enemy_id, "r7_e0")
	assert_true(d.is_boss, "boss room enemy is flagged for the boss-kill bonus")

func test_plan_enemy_powerup_room_returns_null():
	var r := _make_powerup_room(2)
	assert_null(RoomSpawnPlanner.plan_enemy(r), "power-up rooms have no enemy")

func test_plan_enemy_start_room_returns_null():
	var r := _make_start_room(0)
	assert_null(RoomSpawnPlanner.plan_enemy(r), "start rooms have no enemy")

func test_plan_enemy_null_room_returns_null():
	assert_null(RoomSpawnPlanner.plan_enemy(null), "null room is safe no-op")

func test_plan_enemy_returns_independent_instances():
	# Two calls on the same room should not return the same EnemyData
	# reference (mutating one's hp shouldn't drain the other's).
	var r := _make_standard_room(1)
	var a := RoomSpawnPlanner.plan_enemy(r)
	var b := RoomSpawnPlanner.plan_enemy(r)
	a.take_damage(99)
	assert_eq(a.hp, 0)
	assert_eq(b.hp, b.max_hp, "second instance untouched by first's damage")

func test_plan_enemy_spawn_idx_appears_in_id():
	var r := _make_standard_room(5, EnemyData.EnemyKind.BAT)
	var d := RoomSpawnPlanner.plan_enemy(r, 2)
	assert_eq(d.enemy_id, "r5_e2", "spawn_idx threads through to id")

func test_plan_enemy_max_hp_matches_kind():
	# Pin that we go through EnemyData.make_new (so future stat changes
	# in EnemyData propagate without the planner having to re-pin them).
	var r := _make_standard_room(0, EnemyData.EnemyKind.RAT)
	var d := RoomSpawnPlanner.plan_enemy(r)
	assert_eq(d.max_hp, EnemyData.base_max_hp_for(EnemyData.EnemyKind.RAT))
	assert_eq(d.attack, EnemyData.base_attack_for(EnemyData.EnemyKind.RAT))

# --- plan_powerup ----------------------------------------------------------

func test_plan_powerup_powerup_room_returns_type():
	var r := _make_powerup_room(2, "catnip")
	assert_eq(RoomSpawnPlanner.plan_powerup(r), "catnip")

func test_plan_powerup_returns_each_seeded_type():
	# Locks the contract that whatever the generator seeded (via
	# DungeonGenerator's POWER_UP_TYPES pool) round-trips through the
	# planner unchanged.
	for t in ["catnip", "ale", "mushrooms"]:
		assert_eq(RoomSpawnPlanner.plan_powerup(_make_powerup_room(1, t)), t)

func test_plan_powerup_standard_room_returns_empty():
	# A standard room never has a power_up_type seeded by the generator,
	# but defensively reject even if some future code path leaks one in
	# — the planner's gate is room.type, not the field's truthiness.
	var r := _make_standard_room(3)
	r.power_up_type = "catnip"
	assert_eq(RoomSpawnPlanner.plan_powerup(r), "", "non-powerup rooms return empty regardless of field")

func test_plan_powerup_boss_room_returns_empty():
	assert_eq(RoomSpawnPlanner.plan_powerup(_make_boss_room(7)), "")

func test_plan_powerup_start_room_returns_empty():
	assert_eq(RoomSpawnPlanner.plan_powerup(_make_start_room(0)), "")

func test_plan_powerup_null_room_returns_empty():
	assert_eq(RoomSpawnPlanner.plan_powerup(null), "", "null room is safe no-op")

func test_plan_powerup_unknown_type_passes_through():
	# The planner does not validate against PowerUpEffect's known set;
	# the late gate is PowerUpEffect.make at pickup time. A stale-save
	# typo or a future-power-up id flows through as-is.
	var r := _make_powerup_room(1, "espresso")
	assert_eq(RoomSpawnPlanner.plan_powerup(r), "espresso")

func test_plan_powerup_no_overlap_with_plan_enemy():
	# Pin that the two planner outputs are mutually exclusive per room:
	# a room either has an enemy or a power-up, never both. The future
	# spawner branches on which planner returned non-empty.
	var combat := _make_standard_room(1)
	assert_not_null(RoomSpawnPlanner.plan_enemy(combat))
	assert_eq(RoomSpawnPlanner.plan_powerup(combat), "")

	var powerup := _make_powerup_room(2, "ale")
	assert_null(RoomSpawnPlanner.plan_enemy(powerup))
	assert_eq(RoomSpawnPlanner.plan_powerup(powerup), "ale")

# --- enemy_ids_for_room ----------------------------------------------------

func test_enemy_ids_for_standard_room_one_id():
	var r := _make_standard_room(4)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(r)
	assert_eq(ids.size(), 1, "one enemy per combat room today")
	assert_eq(ids[0], "r4_e0")

func test_enemy_ids_for_boss_room_one_id():
	var r := _make_boss_room(9)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(r)
	assert_eq(ids.size(), 1)
	assert_eq(ids[0], "r9_e0")

func test_enemy_ids_for_powerup_room_empty():
	assert_eq(RoomSpawnPlanner.enemy_ids_for_room(_make_powerup_room(2)).size(), 0)

func test_enemy_ids_for_start_room_empty():
	assert_eq(RoomSpawnPlanner.enemy_ids_for_room(_make_start_room(0)).size(), 0)

func test_enemy_ids_for_null_room_empty():
	assert_eq(RoomSpawnPlanner.enemy_ids_for_room(null).size(), 0)

func test_enemy_ids_match_plan_enemy_output():
	# Locks the contract that ids_for_room and plan_enemy agree on the
	# id format — so the per-room watcher's expected-id list and the
	# spawner's actual-EnemyData list don't drift.
	var r := _make_standard_room(11)
	var planned := RoomSpawnPlanner.plan_enemy(r)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(r)
	assert_eq(ids.size(), 1)
	assert_eq(ids[0], planned.enemy_id)

# --- register_room_enemies -------------------------------------------------

func test_register_room_enemies_combat_room_registers_with_session():
	var session := _make_session_with_lobby()
	var room := _make_standard_room(3)
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].enemy_id, "r3_e0")
	assert_true(session.enemy_sync.is_alive("r3_e0"), "registry knows about the spawn")

func test_register_room_enemies_boss_room_sets_is_boss_and_registers():
	var session := _make_session_with_lobby()
	var room := _make_boss_room(7)
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_eq(spawned.size(), 1)
	assert_true(spawned[0].is_boss)
	assert_true(session.enemy_sync.is_alive("r7_e0"))

func test_register_room_enemies_powerup_returns_empty_no_registry_change():
	var session := _make_session_with_lobby()
	var before := session.enemy_sync.alive_count()
	var spawned := RoomSpawnPlanner.register_room_enemies(session, _make_powerup_room(2))
	assert_eq(spawned.size(), 0)
	assert_eq(session.enemy_sync.alive_count(), before, "no registry pollution from powerup room")

func test_register_room_enemies_null_session_still_returns_data():
	# Solo / pre-handshake path: session is null. Caller still gets a
	# populated EnemyData (so it can spawn into the scene tree); the
	# kill flow's empty-registry short-circuit keeps solo correct.
	var spawned := RoomSpawnPlanner.register_room_enemies(null, _make_standard_room(1))
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].enemy_id, "r1_e0")
	assert_false(spawned[0].is_boss)

func test_register_room_enemies_null_room_safe():
	var session := _make_session_with_lobby()
	var spawned := RoomSpawnPlanner.register_room_enemies(session, null)
	assert_eq(spawned.size(), 0, "null room is a safe no-op")

func test_register_room_enemies_session_post_end_safe():
	# Defensive: a race where end() drops enemy_sync before the spawner
	# stops calling. Should still return populated data (so the
	# spawner's instantiation path doesn't crash) without a registry
	# touch.
	var session := _make_session_with_lobby()
	session.end()
	var spawned := RoomSpawnPlanner.register_room_enemies(session, _make_standard_room(1))
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].enemy_id, "r1_e0")

func test_register_room_enemies_idempotent_on_repeat():
	# Mirrors EnemyStateSyncManager.register_enemy's idempotency: a
	# re-register (e.g. spawn-event re-broadcast) returns the same
	# data without polluting the registry.
	var session := _make_session_with_lobby()
	var room := _make_standard_room(3)
	RoomSpawnPlanner.register_room_enemies(session, room)
	var before := session.enemy_sync.alive_count()
	var second := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_eq(second.size(), 1, "second call still returns the planned spawn")
	assert_eq(session.enemy_sync.alive_count(), before, "no registry growth on repeat")

# --- end-to-end: spawn -> kill -> apply_death --------------------------------

func _generate_dungeon_with_layout(seed: int = 1234) -> Array:
	# Returns [dungeon, layout] from the production generator + engine so the
	# multi-room tests cover the same code path as production. Seed is fixed so
	# the assertion shape (room types, ids) is deterministic.
	var d := DungeonGenerator.generate(seed)
	var layout := DungeonLayoutEngine.new().compute(d)
	return [d, layout]

# --- register_all_room_enemies (multi-room, issue #96) ---------------------

func test_register_all_room_enemies_returns_one_id_per_combat_room():
	# Core wiring: every STANDARD + BOSS room in the dungeon mints exactly one
	# enemy id at dungeon load (vs. the lazy per-room-enter pattern this
	# replaces). START + POWERUP rooms produce no ids.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(dungeon, layout)
	var combat_room_count := 0
	for r in dungeon.rooms:
		if r.type == Room.TYPE_STANDARD or r.type == Room.TYPE_BOSS:
			combat_room_count += 1
	assert_eq(ids.size(), combat_room_count,
		"one enemy_id per combat room")

func test_register_all_room_enemies_assigns_spawn_position_from_layout():
	# Each combat room's EnemyData.spawn_position equals the layout's
	# room_center_world(room_id). Locks the contract the scene-tree spawner
	# reads to drop the Enemy node at the right pixel coordinate.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	for r in dungeon.rooms:
		if r.type != Room.TYPE_STANDARD and r.type != Room.TYPE_BOSS:
			continue
		var data := planner.enemy_data_for_room(r.id)
		assert_not_null(data, "combat room %d has planned data" % r.id)
		assert_eq(data.spawn_position, layout.room_center_world(r.id),
			"room %d spawn_position matches layout center" % r.id)

func test_register_all_room_enemies_skips_non_combat_rooms():
	# START and POWERUP rooms must not have a planned EnemyData — the
	# scene-tree spawner reads enemy_data_for_room as the gate for "should I
	# instantiate an enemy here?".
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	for r in dungeon.rooms:
		if r.type == Room.TYPE_START or r.type == Room.TYPE_POWERUP:
			assert_null(planner.enemy_data_for_room(r.id),
				"non-combat room %d (%s) has no planned enemy" % [r.id, r.type])

func test_register_all_room_enemies_marks_boss_room_with_is_boss():
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	var boss := planner.enemy_data_for_room(dungeon.boss_id)
	assert_not_null(boss, "boss room has a planned enemy")
	assert_true(boss.is_boss, "boss room enemy carries the is_boss flag")

func test_register_all_room_enemies_uses_stable_id_format():
	# enemy_id format remains "r{room_id}_e{spawn_idx}" — the wire layer's
	# OP_KILL packet and the per-room watcher's expected set both depend on
	# this format. A drift here would break remote-kill apply at the receiver.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout)
	for r in dungeon.rooms:
		if r.type != Room.TYPE_STANDARD and r.type != Room.TYPE_BOSS:
			continue
		var data := planner.enemy_data_for_room(r.id)
		assert_eq(data.enemy_id, "r%d_e0" % r.id)

func test_register_all_room_enemies_registers_each_id_with_session():
	# Co-op path: every minted id is present in session.enemy_sync so the
	# remote-kill receive flow's apply_death finds it on the receiving client.
	var session := _make_session_with_lobby()
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(dungeon, layout, session)
	for id in ids:
		assert_true(session.enemy_sync.is_alive(id),
			"session.enemy_sync knows about every planned id: %s" % id)

func test_register_all_room_enemies_null_session_still_returns_ids():
	# Solo path: session is null. The planner still mints and stores data so
	# the scene-tree spawner can instantiate the Enemy nodes; the wire layer's
	# empty-registry short-circuit keeps solo behavior unchanged.
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(dungeon, layout, null)
	assert_gt(ids.size(), 0, "solo path still mints ids")
	var boss := planner.enemy_data_for_room(dungeon.boss_id)
	assert_not_null(boss)

func test_register_all_room_enemies_idempotent_on_repeat_call():
	# A second call rebuilds the internal map from scratch but does not pollute
	# the session registry (register_enemy is idempotent). Mirrors the
	# scene-reload pattern that may double-fire register during the
	# advance_to->reload deprecation in #97.
	var session := _make_session_with_lobby()
	var pair = _generate_dungeon_with_layout()
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var planner := RoomSpawnPlanner.new()
	planner.register_all_room_enemies(dungeon, layout, session)
	var before := session.enemy_sync.alive_count()
	var second := planner.register_all_room_enemies(dungeon, layout, session)
	assert_eq(session.enemy_sync.alive_count(), before,
		"no registry growth on repeat call")
	assert_eq(second.size(), planner.planned_room_ids().size(),
		"second call still returns the full id list")

func test_register_all_room_enemies_null_dungeon_safe():
	var planner := RoomSpawnPlanner.new()
	var ids := planner.register_all_room_enemies(null, null)
	assert_eq(ids.size(), 0, "null dungeon is a safe no-op")

func test_enemy_data_for_room_unknown_id_returns_null():
	var planner := RoomSpawnPlanner.new()
	assert_null(planner.enemy_data_for_room(999),
		"unknown room id returns null before any planning")

func test_planned_enemy_id_round_trips_through_apply_death():
	# Pins that the id minted by the planner is the same key
	# KillRewardRouter / EnemyStateSyncManager.apply_death use, so a
	# kill flow against a planned spawn idempotently clears the
	# registry.
	var session := _make_session_with_lobby()
	var room := _make_boss_room(4)
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room)
	assert_true(session.enemy_sync.is_alive(spawned[0].enemy_id))
	assert_true(session.enemy_sync.apply_death(spawned[0].enemy_id))
	assert_false(session.enemy_sync.is_alive(spawned[0].enemy_id))
