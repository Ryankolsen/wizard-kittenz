extends GutTest

# Slice 1 of PRD #223 / issue #224. WeaponPivot is a Node2D + child Sprite2D.
# Tests drive the public swing/interrupt/tick interface deterministically —
# tick(dt) consumes float time instead of awaiting scene-tree timers so the
# unit suite stays sync and fast.

const _WeaponPivotScene = preload("res://scenes/weapon_pivot.tscn")

var _spawned: Array = []

func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.free()
	_spawned.clear()

func _make() -> WeaponPivot:
	var pivot: WeaponPivot = _WeaponPivotScene.instantiate()
	_spawned.append(pivot)
	pivot.set_definition(WeaponDefinition.battle())
	return pivot

# Test 1 from issue #224 — core wiring: swing advances through the full
# windup → strike → recovery span and returns to idle rotation.
func test_swing_returns_to_idle_after_full_duration() -> void:
	var pivot := _make()
	var def := pivot.definition
	pivot.swing(Vector2.RIGHT)
	assert_eq(pivot.phase, WeaponPivot.Phase.WINDUP)
	pivot.tick(def.total_duration() + 0.01)
	assert_eq(pivot.phase, WeaponPivot.Phase.IDLE)
	assert_almost_eq(pivot.rotation, def.idle_rotation, 0.001)

# Mid-swing the rotation crosses the strike apex — verifies the lerp isn't
# clamped early or skipped over.
func test_rotation_reaches_strike_apex_at_strike_phase_end() -> void:
	var pivot := _make()
	var def := pivot.definition
	pivot.swing(Vector2.RIGHT)
	pivot.tick(def.windup_duration)
	pivot.tick(def.strike_duration)
	# At strike-phase end, rotation == idle + swing_arc (for right-facing).
	var expected: float = def.idle_rotation + def.swing_arc
	assert_almost_eq(pivot.rotation, expected, 0.05)

# Test 4 from issue #224 — edge: interrupt resets pivot to idle rotation
# within one frame (tick(0) is "within one frame" since interrupt itself
# already snaps).
func test_interrupt_resets_to_idle_rotation() -> void:
	var pivot := _make()
	var def := pivot.definition
	pivot.swing(Vector2.RIGHT)
	pivot.tick(def.windup_duration * 0.5)
	assert_ne(pivot.rotation, def.idle_rotation)
	pivot.interrupt()
	assert_eq(pivot.phase, WeaponPivot.Phase.IDLE)
	assert_almost_eq(pivot.rotation, def.idle_rotation, 0.001)

# Facing left mirrors the swing direction (PRD user story 9).
func test_swing_left_arcs_in_opposite_direction() -> void:
	var pivot := _make()
	var def := pivot.definition
	pivot.swing(Vector2.LEFT)
	pivot.tick(def.windup_duration)
	pivot.tick(def.strike_duration)
	var expected: float = def.idle_rotation - def.swing_arc
	assert_almost_eq(pivot.rotation, expected, 0.05)
