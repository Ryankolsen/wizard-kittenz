extends GutTest

# Test subclass for the override-counter case (acceptance criterion 2).
class _CounterBehavior extends EnemyBehavior:
	var count: int = 0
	var last_delta: float = 0.0
	var last_enemy = null
	func tick(delta: float, enemy) -> void:
		count += 1
		last_delta = delta
		last_enemy = enemy


func test_base_tick_is_safe_no_op():
	# Acceptance #1: base interface is callable and does not crash.
	var b := EnemyBehavior.new()
	b.tick(0.1, null)
	assert_true(true, "base tick must not crash")


func test_subclass_can_override_tick():
	# Acceptance #2: subclasses override the hook and get the delta + enemy.
	var b := _CounterBehavior.new()
	var fake_enemy := RefCounted.new()
	b.tick(0.1, fake_enemy)
	b.tick(0.1, fake_enemy)
	b.tick(0.1, fake_enemy)
	assert_eq(b.count, 3, "tick override should have fired 3 times")
	assert_almost_eq(b.last_delta, 0.1, 0.0001)
	assert_eq(b.last_enemy, fake_enemy, "enemy arg should pass through")


func test_tick_with_null_enemy_is_safe():
	# Acceptance #4: null kind / missing enemy must not crash the tick path.
	var base := EnemyBehavior.new()
	base.tick(0.1, null)
	var sub := _CounterBehavior.new()
	sub.tick(0.1, null)
	assert_eq(sub.count, 1, "subclass tick with null enemy still increments")


func test_for_kind_returns_non_null_for_every_enum_value():
	# Acceptance #4 (factory side): the dispatch table is exhaustive over the
	# EnemyKind enum, so even kinds without a registered subclass yet return
	# the base no-op rather than null.
	for kind in EnemyData.EnemyKind.values():
		var b := EnemyBehavior.for_kind(kind)
		assert_not_null(b, "for_kind(%d) returned null" % kind)
		# Sanity-check the returned object is at least a base instance and
		# its tick is safe to call.
		b.tick(0.05, null)


func test_for_kind_returns_independent_instances():
	# Each call should mint a fresh instance so per-enemy state (cooldowns,
	# charge timers, projectile lists) doesn't leak across spawns.
	var a := EnemyBehavior.for_kind(EnemyData.EnemyKind.ANGRY_PIGEON)
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_ne(a, b, "for_kind should return distinct instances per call")
