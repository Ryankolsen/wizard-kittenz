extends GutTest

# EnrageAbility (PRD #518 / issue #575). Last Call Larry's low-HP speed and
# damage spike. Same _MockEnemy/_MockData shape as test_zone_denial_ability.gd
# extended with an hp/max_hp pair, since this archetype's trigger is HP,
# not aggro cadence, and it mutates enemy.move_speed and enemy.data.attack
# directly (the same fields RogueRoombaBehavior.berserk and Enemy.data.attack
# already use).

class _MockData:
	var hp: int = 10
	var max_hp: int = 10
	var attack: int = 4

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var move_speed: float = 100.0
	var data: _MockData = _MockData.new()
	var _player_ref = null


# --- 1. Core wiring ----------------------------------------------------------

func test_enrage_fires_once_hp_first_falls_to_or_below_threshold():
	var b := EnrageAbility.new(0.3, 1.5, 1.5)
	var e := _MockEnemy.new()
	e.data.hp = 10
	e.data.max_hp = 10
	b.tick(0.1, e)
	assert_false(b.has_enraged, "enrage must not fire while HP is above the threshold")
	e.data.hp = 3  # 30% of 10, at the threshold
	b.tick(0.1, e)
	assert_true(b.has_enraged, "enrage must fire once HP falls to or below the threshold")


# --- 2. One-shot --------------------------------------------------------------

func test_enrage_never_fires_a_second_time_even_after_hp_recovers():
	var b := EnrageAbility.new(0.3, 1.5, 1.5)
	var e := _MockEnemy.new()
	e.data.hp = 2
	b.tick(0.1, e)
	assert_eq(b.enrage_entry_count, 1, "enrage should have fired exactly once")
	e.data.hp = 10  # HP recovers back above the threshold
	b.tick(0.1, e)
	e.data.hp = 1  # and falls below the threshold again
	b.tick(0.1, e)
	assert_eq(b.enrage_entry_count, 1,
		"enrage must never re-fire, even if HP rises back above the threshold and falls again")


# --- 3. Applied once ----------------------------------------------------------

func test_speed_and_damage_are_multiplied_exactly_once():
	var b := EnrageAbility.new(0.3, 1.5, 2.0)
	var e := _MockEnemy.new()
	e.move_speed = 100.0
	e.data.attack = 4
	e.data.hp = 2
	b.tick(0.1, e)
	assert_almost_eq(e.move_speed, 150.0, 0.001, "speed must be multiplied by the configured factor")
	assert_almost_eq(float(e.data.attack), 8.0, 0.001, "damage must be multiplied by the configured factor")
	# Further ticks at the same low HP must not compound the multiplier again.
	b.tick(0.1, e)
	b.tick(0.1, e)
	assert_almost_eq(e.move_speed, 150.0, 0.001, "speed must not compound across subsequent ticks")
	assert_almost_eq(float(e.data.attack), 8.0, 0.001, "damage must not compound across subsequent ticks")


# --- 4. No zone ----------------------------------------------------------------

func test_enrage_publishes_no_zone_and_is_not_abandoned_by_the_pump():
	var b := EnrageAbility.new(0.3, 1.5, 1.5)
	var e := _MockEnemy.new()
	e.data.hp = 1
	b.tick(0.1, e)
	assert_true(b.has_enraged, "sanity: enrage fired")
	assert_null(b.pending_zone, "enrage must never publish a danger zone")
	assert_false(b.is_active(), "enrage must never enter the pump's active-zone state")
	# A direct call into the pump's begin() (the null-zone path the base class
	# treats as "conditions weren't right, abandon the firing") must not wreck
	# this ability's bookkeeping -- it stays tick-driven and safe to keep
	# ticking afterward.
	b.begin(e)
	assert_null(b.pending_zone, "begin()'s null-zone path must not fabricate a zone")
	assert_false(b.is_active(), "begin()'s null-zone path must not mark this ability active")
	b.tick(0.1, e)
	assert_true(b.has_enraged, "ticking after a declined begin() must still reflect the earlier firing")


# --- 5. Edge cases --------------------------------------------------------------

func test_hp_exactly_at_threshold_fires_inclusive():
	var b := EnrageAbility.new(0.3, 1.5, 1.5)
	var e := _MockEnemy.new()
	e.data.hp = 3
	e.data.max_hp = 10  # exactly 30% -- the intended rule is inclusive (<=)
	b.tick(0.1, e)
	assert_true(b.has_enraged, "HP exactly at the threshold fraction must fire (inclusive rule)")

func test_hp_at_zero_fires():
	var b := EnrageAbility.new(0.3, 1.5, 1.5)
	var e := _MockEnemy.new()
	e.data.hp = 0
	b.tick(0.1, e)
	assert_true(b.has_enraged, "zero HP is well below the threshold and must fire")

func test_already_dead_enemy_does_not_fire():
	var b := EnrageAbility.new(0.3, 1.5, 1.5)
	var e := _MockEnemy.new()
	e.data.hp = 0
	e.state = 3  # EnemyAIState.State.DEAD
	b.tick(0.1, e)
	assert_false(b.has_enraged, "a dead enemy must never enrage")

func test_null_enemy_is_safe():
	var b := EnrageAbility.new(0.3, 1.5, 1.5)
	b.tick(0.1, null)
	assert_false(b.has_enraged, "a null enemy must not fire and must not crash")
