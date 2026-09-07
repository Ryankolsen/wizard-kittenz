extends GutTest

# Retreat and fire archetype (PRD #518 / issue #537). Old Lady Pearl's other
# half: kites at a preferred range with a deadband so it holds rather than
# oscillating, and fires projectiles on an interval while at range. This
# generalises the kiting logic the catnip dealer and haunted spray bottle
# already implement by hand (CatnipDealerBehavior.desired_direction /
# HauntedSprayBottleBehavior.desired_direction) — same mock shapes, same
# direction-test structure.

class _MockPlayer extends Node2D:
	pass

class _MockData:
	var enemy_id: String = ""

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null
	var data: _MockData = _MockData.new()


# --- 6. Core wiring ------------------------------------------------------------

func test_direction_points_away_inside_preferred_range_and_toward_outside_it():
	var b := RetreatAndFireAbility.new()
	var far_dir := b.desired_direction(Vector2.ZERO, Vector2(1000.0, 0.0))
	assert_eq(far_dir, Vector2(1.0, 0.0), "outside preferred range the enemy should approach")
	var near_dir := b.desired_direction(Vector2.ZERO, Vector2(10.0, 0.0))
	assert_eq(near_dir, Vector2(-1.0, 0.0), "inside preferred range the enemy should back away")


# --- 7. Deadband -----------------------------------------------------------------

func test_zero_velocity_within_deadband_around_preferred_range():
	var b := RetreatAndFireAbility.new()
	var dir := b.desired_direction(Vector2.ZERO, Vector2(RetreatAndFireAbility.PREFERRED_RANGE, 0.0))
	assert_eq(dir, Vector2.ZERO, "inside the deadband the enemy should hold rather than oscillate")


# --- 8. Fire cadence ---------------------------------------------------------------

func test_fire_published_once_per_interval_not_every_frame():
	var b := RetreatAndFireAbility.new()
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(RetreatAndFireAbility.PREFERRED_RANGE, 0.0)
	e._player_ref = p
	b.tick(0.1, e)
	assert_null(b.pending_fire_target, "a single small tick must not publish a fire request")
	for _i in range(int(ceil(RetreatAndFireAbility.FIRE_INTERVAL / 0.1)) + 1):
		b.tick(0.1, e)
	assert_not_null(b.pending_fire_target, "fire should publish once the interval elapses")


func test_no_fire_while_inside_flee_threshold():
	var b := RetreatAndFireAbility.new()
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(RetreatAndFireAbility.FLEE_RANGE * 0.5, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(RetreatAndFireAbility.FIRE_INTERVAL / 0.1)) + 5):
		b.tick(0.1, e)
	assert_null(b.pending_fire_target, "no fire should publish while the player is inside the flee threshold")


# --- 9. Edge cases -------------------------------------------------------------------

func test_player_exactly_at_enemy_position_returns_a_safe_direction():
	var b := RetreatAndFireAbility.new()
	var dir := b.desired_direction(Vector2.ZERO, Vector2.ZERO)
	assert_almost_eq(dir.length(), 1.0, 0.0001,
		"a coincident player must not crash and should return a unit direction, not NaN/zero")


func test_player_beyond_max_projectile_range_does_not_fire():
	var b := RetreatAndFireAbility.new()
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(RetreatAndFireAbility.PROJECTILE_MAX_RANGE * 3.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(RetreatAndFireAbility.FIRE_INTERVAL / 0.1)) + 5):
		b.tick(0.1, e)
	assert_null(b.pending_fire_target, "a player beyond max projectile range must not draw fire")


func test_idle_enemy_does_not_fire():
	var b := RetreatAndFireAbility.new()
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	var p := _MockPlayer.new()
	p.global_position = Vector2(RetreatAndFireAbility.PREFERRED_RANGE, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(RetreatAndFireAbility.FIRE_INTERVAL / 0.1)) + 5):
		b.tick(0.1, e)
	assert_null(b.pending_fire_target, "IDLE enemy must not fire even with a player in range")
