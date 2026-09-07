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


# --- Constructor tuning / telegraph flag (issue #582 amendment) -----------------
#
# retreat_and_fire_ability.gd was originally read-only in the PRD's ability
# migration issues, but as written it had no constructor at all — hardcoded
# Pearl's own numbers as class consts, with no way for another caller to bring
# its own tuning or opt into a telegraph. #582 adds constructor parameters for
# every tuning value, each defaulted to Pearl's existing constants, plus an
# opt-in telegraph flag defaulted to false, so Pearl's own no-args call site
# (pearl_loadout) keeps behaving exactly as before while the Catnip Dealer can
# now compose this same archetype with his own numbers and the telegraph on.

func test_constructor_defaults_match_pearls_current_tuning():
	# Test 7: RetreatAndFireAbility.new() with no arguments must produce the
	# exact tuning Pearl's loadout relies on today, and telegraph must default
	# to false so a caller that passes nothing gets the pre-#582 behavior.
	var b := RetreatAndFireAbility.new()
	assert_almost_eq(b.preferred_range(), RetreatAndFireAbility.PREFERRED_RANGE, 0.0001)
	assert_almost_eq(b.flee_range(), RetreatAndFireAbility.FLEE_RANGE, 0.0001)
	assert_almost_eq(b.range_deadband(), RetreatAndFireAbility.RANGE_DEADBAND, 0.0001)
	assert_almost_eq(b.fire_interval(), RetreatAndFireAbility.FIRE_INTERVAL, 0.0001)
	assert_almost_eq(b.projectile_speed(), RetreatAndFireAbility.PROJECTILE_SPEED, 0.0001)
	assert_almost_eq(b.projectile_radius(), RetreatAndFireAbility.PROJECTILE_RADIUS, 0.0001)
	assert_eq(b.projectile_color(), RetreatAndFireAbility.PROJECTILE_COLOR)
	assert_almost_eq(
		b.projectile_max_range(), RetreatAndFireAbility.PROJECTILE_MAX_RANGE, 0.0001)
	assert_false(b.telegraph_enabled(), "telegraph flag should default to false")


func test_constructor_overrides_apply_and_telegraph_flag_gates_the_zone_pump():
	# Test 8: passing explicit tuning + true for telegraph produces an instance
	# using those values; leaving the flag false (even with a very short fire
	# interval) must never publish a danger zone — the no-telegraph path stays
	# the default, inline-fire behavior for any caller that passes nothing for
	# it specifically.
	var tuned := RetreatAndFireAbility.new(
		200.0, 60.0, 12.0, 3.0, 180.0, 10.0, Color(1.0, 0.0, 0.0, 1.0), 400.0, true)
	assert_almost_eq(tuned.preferred_range(), 200.0, 0.0001)
	assert_almost_eq(tuned.flee_range(), 60.0, 0.0001)
	assert_almost_eq(tuned.range_deadband(), 12.0, 0.0001)
	assert_almost_eq(tuned.fire_interval(), 3.0, 0.0001)
	assert_almost_eq(tuned.projectile_speed(), 180.0, 0.0001)
	assert_almost_eq(tuned.projectile_radius(), 10.0, 0.0001)
	assert_eq(tuned.projectile_color(), Color(1.0, 0.0, 0.0, 1.0))
	assert_almost_eq(tuned.projectile_max_range(), 400.0, 0.0001)
	assert_true(tuned.telegraph_enabled())

	var no_telegraph := RetreatAndFireAbility.new(200.0, 60.0, 12.0, 0.05)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(200.0, 0.0)
	e._player_ref = p
	for _i in range(5):
		no_telegraph.tick(0.1, e)
	assert_null(no_telegraph.active_zone,
		"telegraph left false must never publish a danger zone, even past its fire interval")


func test_telegraph_enabled_publishes_a_zone_before_the_fire_target_commits():
	# Companion to test 8: with the flag on, the wind-up must be visible (an
	# active zone in its WINDUP phase) strictly before any pending_fire_target
	# is published — this is what "the throw telegraphs before it commits"
	# means mechanically.
	var b := RetreatAndFireAbility.new(140.0, 50.0, 10.0, 0.2, 170.0, 6.0,
		Color(0.85, 0.8, 0.7, 1.0), 360.0, true)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(140.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.fire_interval() / 0.05)) + 1):
		b.tick(0.05, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_not_null(b.active_zone, "the fire interval elapsing should have begun a telegraph zone")
	assert_eq(b.active_zone.phase_at(b.zone_elapsed()), DangerZoneShape.Phase.WINDUP,
		"the zone should still be winding up immediately after begin()")
	assert_null(b.pending_fire_target, "no fire target should exist before the zone commits")
	for _i in range(200):
		b.tick(0.01, e)
		if b.pending_fire_target != null:
			break
	assert_not_null(b.pending_fire_target, "the throw should commit once the zone reaches COMMIT")
