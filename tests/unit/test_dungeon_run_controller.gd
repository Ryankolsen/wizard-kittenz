extends GutTest

# Tests for DungeonRunController — the room-transition data layer's run-state
# machine. Each helper builds a tiny hand-rolled Dungeon graph so the test
# isn't coupled to DungeonGenerator's stochastic shape; the generator is
# tested independently in test_dungeon_generator.gd.

func _make_linear_dungeon() -> Dungeon:
	# start(0) -> standard(1) -> boss(2). Linear so connection semantics are
	# unambiguous in advance_to tests.
	var d := Dungeon.new()
	var s := Room.make(0, Room.TYPE_START)
	var n := Room.make(1, Room.TYPE_STANDARD)
	n.enemy_kind = EnemyData.EnemyKind.SLIME
	var b := Room.make(2, Room.TYPE_BOSS)
	b.enemy_kind = EnemyData.EnemyKind.RAT
	s.connections = [1]
	n.connections = [2]
	d.add_room(s)
	d.add_room(n)
	d.add_room(b)
	d.start_id = 0
	d.boss_id = 2
	return d

func _make_branching_dungeon() -> Dungeon:
	# start(0) -> standard(1), powerup(2) -> boss(3). Two children of start
	# so connection-membership is meaningful (advance to a non-listed id
	# should fail).
	var d := Dungeon.new()
	var s := Room.make(0, Room.TYPE_START)
	var n := Room.make(1, Room.TYPE_STANDARD)
	n.enemy_kind = EnemyData.EnemyKind.SLIME
	var p := Room.make(2, Room.TYPE_POWERUP)
	p.power_up_type = "catnip"
	var b := Room.make(3, Room.TYPE_BOSS)
	b.enemy_kind = EnemyData.EnemyKind.RAT
	s.connections = [1, 2]
	n.connections = [3]
	p.connections = [3]
	d.add_room(s)
	d.add_room(n)
	d.add_room(p)
	d.add_room(b)
	d.start_id = 0
	d.boss_id = 3
	return d

# --- start ------------------------------------------------------------------

func test_start_sets_current_room_to_start_id():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	assert_true(c.start(d), "start succeeds on a well-formed dungeon")
	assert_eq(c.current_room_id, 0)
	assert_eq(c.current_room().type, Room.TYPE_START)

func test_start_with_null_dungeon_returns_false():
	var c := DungeonRunController.new()
	assert_false(c.start(null), "null dungeon rejected")
	assert_eq(c.current_room_id, -1)

func test_start_with_negative_start_id_returns_false():
	# A dungeon constructed but never seeded (start_id stays -1) shouldn't
	# silently boot the controller into an invalid state.
	var d := Dungeon.new()
	var c := DungeonRunController.new()
	assert_false(c.start(d), "uninitialized dungeon rejected")

func test_start_resets_cleared_state():
	# Re-running start with a new graph must drop the previous run's
	# cleared flags so the player can re-clear room ids that collide.
	var d1 := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d1)
	c.mark_room_cleared(1)
	assert_true(c.is_room_cleared(1))
	var d2 := _make_linear_dungeon()
	c.start(d2)
	assert_false(c.is_room_cleared(1), "fresh start drops prior cleared flags")

func test_start_emits_advanced_to_for_start_room():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	assert_signal_emitted_with_parameters(c, "advanced_to", [0])

# --- current_room -----------------------------------------------------------

func test_current_room_null_before_start():
	var c := DungeonRunController.new()
	assert_null(c.current_room())

func test_current_room_after_advance():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.mark_room_cleared(0)  # start has no enemy but mark anyway for symmetry
	c.advance_to(1)
	assert_eq(c.current_room().id, 1)
	assert_eq(c.current_room().type, Room.TYPE_STANDARD)

# --- is_room_cleared --------------------------------------------------------

func test_is_room_cleared_false_for_uncleared_combat_room():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_false(c.is_room_cleared(1), "standard combat room defaults uncleared")
	assert_false(c.is_room_cleared(2), "boss room defaults uncleared")

func test_is_room_cleared_auto_for_start_room():
	# Start room has enemy_kind == -1 so it's auto-cleared. Player can step
	# through start without combat.
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_true(c.is_room_cleared(0), "start room (no enemy) auto-cleared")

func test_is_room_cleared_auto_for_powerup_room():
	# Power-up rooms have enemy_kind == -1 so they're auto-cleared too.
	var d := _make_branching_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_true(c.is_room_cleared(2), "powerup room auto-cleared")

func test_is_room_cleared_explicit_after_mark():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.mark_room_cleared(1)
	assert_true(c.is_room_cleared(1))

func test_is_room_cleared_unknown_id_returns_false():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_false(c.is_room_cleared(999), "unknown id is not cleared")

func test_is_room_cleared_before_start_returns_false():
	# Defensive: caller polling cleared state before start() is a logic
	# error but shouldn't crash.
	var c := DungeonRunController.new()
	assert_false(c.is_room_cleared(0))

# --- mark_room_cleared ------------------------------------------------------

func test_mark_room_cleared_first_call_returns_true():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_true(c.mark_room_cleared(1), "first mark on a real room is fresh")

func test_mark_room_cleared_repeat_returns_false():
	# Idempotent: a second mark on the same room is a no-op so the caller
	# can fire the signal at-most-once. Same shape as
	# EnemyStateSyncManager.apply_death.
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.mark_room_cleared(1)
	assert_false(c.mark_room_cleared(1), "second mark is a no-op")

func test_mark_room_cleared_unknown_id_returns_false():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_false(c.mark_room_cleared(999), "unknown id rejected")
	assert_false(c.is_room_cleared(999), "unknown id not stealth-cleared on reject")

func test_mark_room_cleared_before_start_returns_false():
	var c := DungeonRunController.new()
	assert_false(c.mark_room_cleared(0))

func test_mark_room_cleared_emits_room_cleared_signal_once():
	# Edge-trigger: the signal fires once per room, even if the caller
	# accidentally calls mark twice.
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.mark_room_cleared(1)
	c.mark_room_cleared(1)
	assert_signal_emit_count(c, "room_cleared", 1)
	assert_signal_emitted_with_parameters(c, "room_cleared", [1])

func test_mark_room_cleared_boss_emits_dungeon_completed():
	# Boss room cleared is the trigger for DungeonRunCompletion.complete().
	# Locking the signal so the orchestrator can bind to one well-defined
	# edge instead of polling is_dungeon_complete().
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.mark_room_cleared(2)
	assert_signal_emitted(c, "dungeon_completed")
	assert_signal_emit_count(c, "dungeon_completed", 1)

func test_mark_room_cleared_non_boss_does_not_emit_completed():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.mark_room_cleared(1)
	assert_signal_not_emitted(c, "dungeon_completed")

func test_mark_room_cleared_repeat_boss_does_not_re_emit_completed():
	# Idempotency on the terminal edge — the orchestrator's
	# DungeonRunCompletion.complete() must fire exactly once even if the
	# room-clear watcher accidentally re-fires.
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.mark_room_cleared(2)
	c.mark_room_cleared(2)
	assert_signal_emit_count(c, "dungeon_completed", 1)

# --- can_advance_to ---------------------------------------------------------

func test_can_advance_to_connected_room_when_cleared():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	# start has enemy_kind == -1 -> auto-cleared, so we can advance to 1.
	assert_true(c.can_advance_to(1))

func test_can_advance_to_blocks_when_current_uncleared():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.advance_to(1)
	# Standing in room 1 (standard, uncleared). Cannot advance to boss
	# until the standard room's enemy is killed.
	assert_false(c.can_advance_to(2), "uncleared current room blocks advance")

func test_can_advance_to_unlocks_after_clear():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.advance_to(1)
	c.mark_room_cleared(1)
	assert_true(c.can_advance_to(2))

func test_can_advance_to_non_connected_room_returns_false():
	# Branching graph: standing in start (id 0), connections are [1, 2].
	# Trying to skip directly to boss (3) must fail.
	var d := _make_branching_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_false(c.can_advance_to(3), "non-listed connection rejected")

func test_can_advance_to_unknown_room_returns_false():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_false(c.can_advance_to(999))

func test_can_advance_to_before_start_returns_false():
	var c := DungeonRunController.new()
	assert_false(c.can_advance_to(0))

# --- advance_to -------------------------------------------------------------

func test_advance_to_updates_current_room_id():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_true(c.advance_to(1))
	assert_eq(c.current_room_id, 1)

func test_advance_to_emits_advanced_to_signal():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.advance_to(1)
	# Two emissions total: one from start(), one from advance_to(1).
	assert_signal_emit_count(c, "advanced_to", 2)

func test_advance_to_failure_does_not_change_room():
	# Trying to skip past an uncleared room returns false and leaves
	# current_room_id where it was — no partial state transition.
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.advance_to(1)
	assert_false(c.advance_to(2), "uncleared standard room blocks advance")
	assert_eq(c.current_room_id, 1, "room id unchanged after failed advance")

# --- is_dungeon_complete ----------------------------------------------------

func test_is_dungeon_complete_false_until_boss_cleared():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	assert_false(c.is_dungeon_complete())
	c.mark_room_cleared(1)
	assert_false(c.is_dungeon_complete(), "non-boss clear doesn't complete")

func test_is_dungeon_complete_true_after_boss_cleared():
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.mark_room_cleared(2)
	assert_true(c.is_dungeon_complete())

func test_is_dungeon_complete_before_start_returns_false():
	var c := DungeonRunController.new()
	assert_false(c.is_dungeon_complete())

# --- transition / dungeon_transitioned (PRD #52 / #61) ----------------------

func test_transition_emits_dungeon_transitioned_signal():
	# Core wiring: transition() is the orchestrator's "advance to next
	# dungeon" call. Fires the signal so the scene layer can open the
	# stat-allocation screen before the actual scene reload.
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.advance_to(1)
	c.mark_room_cleared(1)
	c.transition()
	assert_signal_emitted(c, "dungeon_transitioned")

func test_transition_distinct_from_dungeon_completed_on_boss_clear():
	# Boss clear fires dungeon_completed (run-end), NOT dungeon_transitioned.
	# transition() is the deliberate orchestrator call, not the combat
	# outcome — keeps the two edges decoupled so a listener can react to
	# "run over" without entangling with "moving to next dungeon."
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.mark_room_cleared(2)
	assert_signal_emitted(c, "dungeon_completed")
	assert_signal_not_emitted(c, "dungeon_transitioned")

func test_transition_does_not_emit_dungeon_completed():
	# Symmetric: transition() fires only its own signal, not dungeon_completed.
	var d := _make_linear_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	c.start(d)
	c.transition()
	assert_signal_not_emitted(c, "dungeon_completed")
	assert_signal_emit_count(c, "dungeon_transitioned", 1)

# --- end-to-end happy path --------------------------------------------------

func test_full_run_through_branching_dungeon_via_powerup():
	# start(0 auto) -> powerup(2 auto) -> boss(3 explicit). The path that
	# avoids the standard combat room. Drives the controller through the
	# whole state machine and asserts the dungeon_completed signal lands
	# at the right moment.
	var d := _make_branching_dungeon()
	var c := DungeonRunController.new()
	watch_signals(c)
	assert_true(c.start(d))
	assert_true(c.advance_to(2), "advance start -> powerup")
	assert_true(c.advance_to(3), "advance powerup -> boss")
	assert_signal_not_emitted(c, "dungeon_completed")
	c.mark_room_cleared(3)
	assert_true(c.is_dungeon_complete())
	assert_signal_emit_count(c, "dungeon_completed", 1)

func test_full_run_through_branching_dungeon_via_combat():
	# Alternate path: start(0) -> standard(1, kill) -> boss(3, kill). Combat
	# room blocks advance until cleared.
	var d := _make_branching_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	c.advance_to(1)
	assert_false(c.advance_to(3), "combat room blocks before clear")
	c.mark_room_cleared(1)
	assert_true(c.advance_to(3))
	c.mark_room_cleared(3)
	assert_true(c.is_dungeon_complete())
