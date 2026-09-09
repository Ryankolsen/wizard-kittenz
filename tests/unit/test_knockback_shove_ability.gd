extends GutTest

# Knockback-shove archetype (PRD #518 / issue #574). Completes Big Bruiser
# Buster: standing in melee gets shoved away, so the fight teaches players to
# respect his space. Displacement reuses PullAbility's shape with the sign
# reversed — same _MockEnemy/_MockPlayer shapes as test_enemy_behavior.gd,
# same tick-driven cooldown/begin pattern as test_ground_slam_ability.gd and
# test_zone_denial_ability.gd (there is no test_pull_ability.gd to mirror
# instead, so direction assertions follow test_retreat_and_fire_ability.gd).

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref = null

class _MockPlayer extends Node2D:
	pass


# --- 1. Core wiring -------------------------------------------------------

func test_commit_moves_player_away_from_enemy():
	var b := KnockbackShoveAbility.new(1.0, 0.1, 0.5, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(30.0, 0.0)
	e._player_ref = p
	var start_dist: float = e.global_position.distance_to(p.global_position)
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var step := 0.02
	var elapsed := 0.0
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
	var end_dist: float = e.global_position.distance_to(p.global_position)
	assert_gt(end_dist, start_dist, "commit should have shoved the player farther from the enemy")


# --- 2. Direction -----------------------------------------------------------

func test_displacement_points_outward_along_enemy_to_player_vector():
	var b := KnockbackShoveAbility.new(1.0, 0.1, 0.5, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(30.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var step := 0.02
	var elapsed := 0.0
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
	# Enemy sits at the origin and the player started on the +X axis: an
	# outward shove must keep (and push farther along) the +X side, unlike
	# PullAbility, which would drag the player back toward/through the enemy.
	assert_gt(p.global_position.x, 30.0,
		"displacement should point away from the enemy along +X")


# --- 3. Range gate -----------------------------------------------------------

func test_out_of_range_player_publishes_no_zone_and_does_not_consume_cooldown():
	var b := KnockbackShoveAbility.new(1.0, 0.1, 0.5, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(500.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.active_zone, "an out-of-range player must never get a published zone")
	assert_true(b.wants_to_fire(),
		"a declined build must leave the cooldown running so the ability keeps retrying")


# --- 4. Escape during wind-up -------------------------------------------------

func test_player_who_leaves_the_zone_during_windup_is_not_shoved():
	var b := KnockbackShoveAbility.new(1.0, 0.5, 0.1, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(30.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	assert_not_null(b.active_zone, "player in range at telegraph start should begin a zone")
	p.global_position = Vector2(500.0, 0.0)
	var step := 0.02
	var elapsed := 0.0
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
	assert_eq(p.global_position, Vector2(500.0, 0.0),
		"a player who left the zone before commit must not be displaced")


# --- 5. Fire-once -------------------------------------------------------------

func test_displacement_happens_once_per_firing_not_once_per_commit_frame():
	var b := KnockbackShoveAbility.new(1.0, 0.05, 0.3, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(30.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var distinct := {}
	var step := 0.01
	var elapsed := 0.0
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
		distinct[p.global_position] = true
	assert_eq(distinct.size(), 2,
		"the player's position should take on exactly two values: pre-shove and post-shove")


# --- 6. Clamp ------------------------------------------------------------------

func test_displacement_magnitude_never_exceeds_configured_maximum():
	var b := KnockbackShoveAbility.new(1.0, 0.05, 0.1, 0.1, 70.0, 40.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(30.0, 0.0)
	e._player_ref = p
	var start: Vector2 = p.global_position
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var step := 0.02
	var elapsed := 0.0
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
	var moved: float = start.distance_to(p.global_position)
	assert_true(moved <= 40.0 + 0.001,
		"displacement must never exceed the configured knockback distance")


# --- 7. Edge cases ---------------------------------------------------------------

func test_player_exactly_at_enemy_position_produces_no_nan():
	var b := KnockbackShoveAbility.new(1.0, 0.05, 0.1, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2.ZERO
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var step := 0.02
	var elapsed := 0.0
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
	assert_false(is_nan(p.global_position.x) or is_nan(p.global_position.y),
		"a coincident player must not produce NaN")


func test_player_exactly_at_melee_boundary_publishes_a_zone():
	var b := KnockbackShoveAbility.new(1.0, 0.05, 0.1, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(70.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	assert_not_null(b.active_zone, "a player exactly at the melee boundary should still fire")


func test_idle_enemy_publishes_nothing():
	var b := KnockbackShoveAbility.new(1.0, 0.05, 0.1, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	var p := _MockPlayer.new()
	p.global_position = Vector2(30.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.active_zone, "an IDLE enemy must never publish a zone")


func test_null_player_does_not_crash():
	var b := KnockbackShoveAbility.new(1.0, 0.05, 0.1, 0.1, 70.0, 90.0)
	var e := _MockEnemy.new()
	e._player_ref = null
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.active_zone, "a null player reference must not crash and must publish nothing")


# --- 8. Second consumer (issue #578) -------------------------------------------

func test_the_bouncers_tuning_is_harder_and_more_frequent_than_busters():
	# The Bouncer reuses this archetype unmodified (out of scope to touch this
	# file for him) -- only AbilityLoadout's tuning differs. His shove is what
	# keeps pushing the player back around to his shielded front, so it must
	# hit harder (more displacement) and recur more often (shorter cooldown)
	# than Buster's own tuning of the same archetype.
	var buster := AbilityLoadout.big_bruiser_buster_loadout()
	var bouncer := AbilityLoadout.the_bouncer_loadout()
	var buster_shove: KnockbackShoveAbility = null
	var bouncer_shove: KnockbackShoveAbility = null
	for ability in buster:
		if ability is KnockbackShoveAbility:
			buster_shove = ability
	for ability in bouncer:
		if ability is KnockbackShoveAbility:
			bouncer_shove = ability
	assert_not_null(buster_shove, "Buster's loadout must carry a knockback shove")
	assert_not_null(bouncer_shove, "The Bouncer's loadout must carry a knockback shove")
	assert_gt(bouncer_shove.knockback_distance(), buster_shove.knockback_distance(),
		"The Bouncer's shove must displace farther than Buster's")
	assert_lt(bouncer_shove.cooldown(), buster_shove.cooldown(),
		"The Bouncer's shove must recur more often than Buster's")
