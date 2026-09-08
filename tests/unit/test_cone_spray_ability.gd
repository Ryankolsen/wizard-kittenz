extends GutTest

# ConeSprayAbility (PRD #518 / issue #576). Karaoke Karen's screech: a
# sustained cone along her facing, locked at telegraph start so flanking
# behind her during the wind-up is a real counter. Same _MockEnemy/_MockPlayer
# shape as test_enemy_behavior.gd (duplicated locally, same convention
# test_zone_denial_ability.gd / test_ground_slam_ability.gd already follow).

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref = null

class _MockPlayer extends Node2D:
	pass


# --- 6. Core wiring -----------------------------------------------------------

func test_cone_zone_published_after_cooldown_originating_at_the_enemy():
	var b := ConeSprayAbility.new()
	var e := _MockEnemy.new()
	e.global_position = Vector2(30.0, -10.0)
	var p := _MockPlayer.new()
	p.global_position = e.global_position + Vector2(100.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_not_null(b.pending_zone, "a cone zone should have been published once the cooldown elapsed")
	assert_eq(b.pending_zone.kind, DangerZoneShape.Kind.CONE,
		"cone spray's telegraph must be a cone, not a lane/tether/disc/ring")
	assert_eq(b.pending_zone.origin, e.global_position,
		"the cone must originate at the enemy's own position")


# --- 7. Facing locked at telegraph start ---------------------------------------

func test_facing_does_not_follow_the_player_during_windup():
	var b := ConeSprayAbility.new(1.0, 1.0, 0.5, 0.1, 180.0, 35.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)  # directly ahead (east)
	e._player_ref = p
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var locked_heading: Vector2 = b.pending_zone.heading
	assert_almost_eq(locked_heading.angle(), Vector2.RIGHT.angle(), 0.01,
		"the cone should lock onto the player's position at telegraph start")
	# Player moves to stand due north of the enemy during the wind-up.
	p.global_position = Vector2(0.0, -100.0)
	b.tick(b.windup_duration() * 0.5, e)
	assert_eq(b.active_zone.heading, locked_heading,
		"the cone's facing must not follow the player once the wind-up has started")


# --- 8. Sustained damage --------------------------------------------------------

func test_damage_ticks_across_the_commit_window_and_stops_at_fade():
	var b := ConeSprayAbility.new(1.0, 0.1, 1.0, 0.3, 180.0, 35.0, 0.2)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(50.0, 0.0)  # directly ahead, well inside the cone
	e._player_ref = p
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var hits := 0
	var step := 0.05
	var elapsed := 0.0
	var total := b.windup_duration() + b.commit_duration() + b.fade_duration() + 0.2
	while elapsed < total:
		b.tick(step, e)
		elapsed += step
		if b.pending_hit_target != null:
			hits += 1
			b.pending_hit_target = null  # simulate the node consuming the handoff
	assert_gt(hits, 1,
		"a sustained cone must land more than one hit across a commit window several ticks long")


func test_no_hit_lands_once_the_zone_reaches_fade():
	var b := ConeSprayAbility.new(1.0, 0.1, 0.3, 0.5, 180.0, 35.0, 0.2)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(50.0, 0.0)
	e._player_ref = p
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	# Advance past commit into fade.
	b.tick(b.windup_duration() + b.commit_duration() + 0.05, e)
	b.pending_hit_target = null
	b.tick(0.1, e)
	assert_null(b.pending_hit_target, "no new hit should land once the zone has faded")


# --- 9. Flank ------------------------------------------------------------------

func test_player_behind_the_enemy_at_commit_is_not_hit():
	var b := ConeSprayAbility.new(1.0, 0.1, 0.5, 0.1, 180.0, 35.0, 0.05)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)  # ahead, so the cone locks facing east
	e._player_ref = p
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	# Player flanks behind the enemy during the wind-up.
	p.global_position = Vector2(-30.0, 0.0)
	var elapsed := 0.0
	var step := 0.02
	var hit := false
	var total := b.windup_duration() + b.commit_duration() + 0.1
	while elapsed < total:
		b.tick(step, e)
		elapsed += step
		if b.pending_hit_target != null:
			hit = true
	assert_false(hit, "a player who flanked behind the enemy during the wind-up must never be caught")


# --- 10. Edge cases --------------------------------------------------------------

func test_idle_enemy_publishes_nothing():
	var b := ConeSprayAbility.new(1.0, 0.1, 0.5, 0.1)
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	for _i in range(5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "an IDLE enemy must not publish a cone zone")


func test_null_player_does_not_crash():
	var b := ConeSprayAbility.new(1.0, 0.1, 0.5, 0.1)
	var e := _MockEnemy.new()
	for _i in range(5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "with no player reference the ability must never build a zone")
	for _i in range(20):
		b.tick(0.1, e)
	assert_null(b.pending_hit_target, "a null player reference must never resolve as hit")


func test_player_exactly_at_enemy_origin_is_caught():
	var b := ConeSprayAbility.new(1.0, 0.1, 0.5, 0.1, 180.0, 35.0, 0.05)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)  # locks facing east
	e._player_ref = p
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	p.global_position = Vector2.ZERO  # stands exactly on the enemy at commit
	var elapsed := 0.0
	var step := 0.02
	var hit := false
	var total := b.windup_duration() + b.commit_duration() + 0.1
	while elapsed < total:
		b.tick(step, e)
		elapsed += step
		if b.pending_hit_target != null:
			hit = true
	assert_true(hit, "a player standing exactly on the enemy must be caught by the cone")
