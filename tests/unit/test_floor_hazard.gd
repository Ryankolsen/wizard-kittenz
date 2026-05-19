extends GutTest

# Tests for the reusable FloorHazard primitive (issue #158). Drives the timer,
# slow, and damage paths directly without a SceneTree — same pattern as
# EnemyProjectile (issue #159) / EnemyBehavior (issue #157).

class _MockTarget:
	var speed: float = 100.0
	var hp: int = 10
	func take_damage(amount: int) -> int:
		var dealt := mini(amount, hp)
		hp -= dealt
		return dealt


var _spawned: Array = []

func _make(duration: float = 2.0, slow_percent: float = 0.0,
		damage_per_sec: float = 0.0) -> FloorHazard:
	var h := FloorHazard.new()
	h.configure(duration, slow_percent, damage_per_sec, 32.0,
		Color(0.5, 0.5, 0.5, 0.4))
	_spawned.append(h)
	return h

func after_each() -> void:
	for h in _spawned:
		if is_instance_valid(h):
			h.free()
	_spawned.clear()


func test_timer_advances_and_expires():
	# Acceptance #3 / test 1: tick advances `elapsed`; is_expired flips when
	# elapsed >= duration.
	var h := _make(2.0)
	assert_almost_eq(h.elapsed, 0.0, 0.0001)
	assert_false(h.is_expired(), "fresh hazard should not be expired")
	h.tick(1.0)
	assert_almost_eq(h.elapsed, 1.0, 0.0001)
	assert_false(h.is_expired(), "1s of 2s should not be expired yet")
	h.tick(1.1)
	assert_true(h.is_expired(), "2.1s of 2s should be expired")


func test_slow_applies_and_restores():
	# Acceptance #2 / test 2: apply_to subtracts slow_percent * speed; remove_from
	# restores exactly the amount subtracted.
	var target := _MockTarget.new()
	target.speed = 100.0
	var h := _make(2.0, 0.3, 0.0)
	h.apply_to(target)
	assert_almost_eq(target.speed, 70.0, 0.0001, "speed should drop to 70 (100 * (1 - 0.3))")
	h.remove_from(target)
	assert_almost_eq(target.speed, 100.0, 0.0001, "speed should restore to 100")


func test_damage_per_sec_floors_fractional_accumulation():
	# Acceptance #2 / test 3: damage_per_sec * delta accumulates and only the
	# whole-integer portion is dealt per tick. With 5 dmg/s and 0.5s delta the
	# accumulator hits 2.5 — 2 damage dealt, 0.5 carried forward.
	var target := _MockTarget.new()
	target.hp = 10
	var h := _make(5.0, 0.0, 5.0)
	h.tick(0.5, target)
	assert_eq(target.hp, 8, "expected 2 damage from 5 dmg/s * 0.5s (floored)")
	# Another 0.5s should push accum from 0.5 + 2.5 = 3.0 → 3 more damage.
	h.tick(0.5, target)
	assert_eq(target.hp, 5, "carrying the 0.5 fraction should yield 3 dmg next tick")


func test_zero_damage_pure_slow():
	# Acceptance #5 / test 4: damage_per_sec = 0 leaves hp untouched even with
	# a target in-zone.
	var target := _MockTarget.new()
	target.hp = 10
	var h := _make(2.0, 0.3, 0.0)
	h.tick(1.0, target)
	assert_eq(target.hp, 10, "zero damage_per_sec should not change hp")


func test_expiry_boundary():
	# Acceptance #3 / test 5: is_expired stays false right up to duration and
	# flips true at/after duration.
	var h := _make(1.0)
	h.tick(0.9)
	assert_false(h.is_expired(), "0.9s of 1.0s should not be expired")
	h.tick(0.05)
	assert_false(h.is_expired(), "0.95s of 1.0s should not be expired")
	h.tick(0.1)
	assert_true(h.is_expired(), "1.05s of 1.0s should be expired")


func test_multiple_hazards_coexist():
	# Acceptance #4: two hazards on independent targets do not interfere.
	var t1 := _MockTarget.new()
	var t2 := _MockTarget.new()
	t1.speed = 100.0
	t2.speed = 80.0
	var a := _make(2.0, 0.3, 0.0)
	var b := _make(2.0, 0.5, 0.0)
	a.apply_to(t1)
	b.apply_to(t2)
	assert_almost_eq(t1.speed, 70.0, 0.0001)
	assert_almost_eq(t2.speed, 40.0, 0.0001)
	a.remove_from(t1)
	b.remove_from(t2)
	assert_almost_eq(t1.speed, 100.0, 0.0001)
	assert_almost_eq(t2.speed, 80.0, 0.0001)


func test_remove_without_apply_is_safe():
	# Defensive: removing when nothing was applied (e.g. target never overlapped)
	# is a no-op rather than wrongly granting +0 speed off a stale delta.
	var target := _MockTarget.new()
	target.speed = 100.0
	var h := _make(2.0, 0.3, 0.0)
	h.remove_from(target)
	assert_almost_eq(target.speed, 100.0, 0.0001, "remove_from without apply should be a no-op")


func test_tick_without_target_advances_timer_only():
	# When no player is overlapping, tick still advances elapsed but no damage
	# accumulation occurs (the accumulator would otherwise drift between
	# overlap windows and front-load the first hit when a player re-enters).
	var h := _make(2.0, 0.0, 5.0)
	h.tick(0.5, null)
	assert_almost_eq(h.elapsed, 0.5, 0.0001)
	assert_false(h.is_expired())
