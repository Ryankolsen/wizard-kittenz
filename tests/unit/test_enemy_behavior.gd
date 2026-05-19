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


# ---------------------------------------------------------------------------
# AngryPigeonBehavior (issue #161) — dive-bomb charge state machine.
# ---------------------------------------------------------------------------

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE

func test_angry_pigeon_charge_timer_counts_down():
	# Issue #161 acceptance #1: charge ~every 4 seconds. Driving four 1.0s
	# ticks against a mock without a player ref accrues the cooldown without
	# auto-triggering the charge — wants_to_charge flips true at the threshold.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	for _i in range(4):
		b.tick(1.0, e)
	assert_true(b.wants_to_charge(), "cooldown should have elapsed after 4 ticks of 1.0s")


func test_angry_pigeon_for_kind_dispatches_subclass():
	# The for_kind factory should hand back an AngryPigeonBehavior for the
	# ANGRY_PIGEON kind so the Enemy node's _ready wiring picks it up without
	# any per-kind branching at the call site.
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_true(b is AngryPigeonBehavior, "ANGRY_PIGEON kind must dispatch to AngryPigeonBehavior")


func test_angry_pigeon_begin_charge_locks_target():
	# Acceptance #2: charge locks a target position. begin_charge captures
	# the coord and flips is_charging so the next tick advances toward it.
	var b := AngryPigeonBehavior.new()
	var target := Vector2(200.0, 50.0)
	b.begin_charge(target)
	assert_eq(b.charge_target, target, "charge_target should match the position passed in")
	assert_true(b.is_charging, "is_charging should be true after begin_charge")
	assert_false(b.charge_completed, "charge_completed should be reset at charge start")


func test_angry_pigeon_charge_ends_on_arrival():
	# Acceptance #3: charge completes when the enemy reaches the target.
	# Drive ticks at a fixed delta and let the behavior step global_position
	# toward charge_target — the arrival check inside tick should flip
	# is_charging false once we're within ARRIVAL_DIST.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	e.global_position = Vector2.ZERO
	b.begin_charge(Vector2(120.0, 0.0))
	# CHARGE_SPEED=120 → 1.0s of travel covers the full 120 px in one tick.
	# Add a couple of extra ticks as a safety net against floating-point drift.
	for _i in range(3):
		b.tick(0.5, e)
		if not b.is_charging:
			break
	assert_false(b.is_charging, "charge should have ended after arrival")
	assert_true(b.charge_completed, "charge_completed should be set on arrival")
	assert_eq(e.global_position, Vector2(120.0, 0.0), "enemy should be snapped to target on completion")


func test_angry_pigeon_pending_hazard_position_set_on_completion():
	# Acceptance #4: on charge completion the impact point is published as
	# `pending_hazard_position` so the Enemy-side observer can spawn the
	# FloorHazard. The data handoff is what we test here; the scene-tree
	# spawn lives in the integration layer.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	var impact := Vector2(80.0, 80.0)
	b.begin_charge(impact)
	# One tick at 1.0s covers 120 px > 80*sqrt(2) ≈ 113 px, so arrival
	# triggers and pending_hazard_position should be the impact point.
	b.tick(1.0, e)
	assert_not_null(b.pending_hazard_position, "pending_hazard_position should be set after completion")
	assert_eq(b.pending_hazard_position, impact, "pending_hazard_position should equal the impact point")


func test_angry_pigeon_dead_enemy_skips_charge():
	# Acceptance #6: a dead pigeon must not accrue cooldown or begin a
	# charge — the DEAD state is the sink the rest of the AI honors.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	e.state = 3  # EnemyAIState.State.DEAD
	for _i in range(6):
		b.tick(1.0, e)
	assert_false(b.wants_to_charge(), "dead enemy should never want to charge")
	assert_false(b.is_charging, "dead enemy should never be charging")
