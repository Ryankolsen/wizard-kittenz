extends GutTest

# GroundSlamAbility (PRD #518 / issue #573). Ground slam is an expanding
# shockwave ring centred on the enemy — the player's counter is getting
# outside the ring before the expanding edge reaches them. Same
# _MockEnemy/_MockPlayer shape as test_enemy_behavior.gd (duplicated locally,
# same convention test_zone_denial_ability.gd already follows).

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref = null

class _MockPlayer extends Node2D:
	pass


# --- 7. Core wiring -----------------------------------------------------------

func test_ring_zone_published_after_cooldown_when_aggroed_centred_on_enemy():
	var b := GroundSlamAbility.new()
	var e := _MockEnemy.new()
	e.global_position = Vector2(30.0, -10.0)
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_not_null(b.pending_zone, "a ring zone should have been published once the cooldown elapsed")
	assert_eq(b.pending_zone.kind, DangerZoneShape.Kind.RING,
		"ground slam's telegraph must be a ring, not a disc/lane/tether")
	assert_eq(b.pending_zone.origin, e.global_position,
		"the ring must be centred on the enemy's own position")


# --- 8. Hit resolution ----------------------------------------------------------

func test_hit_lands_when_wave_passes_player_and_not_beyond_max_radius():
	var b := GroundSlamAbility.new(1.0, 0.1, 1.0, 0.1, 100.0, 20.0)
	var e := _MockEnemy.new()
	var hit_player := _MockPlayer.new()
	hit_player.global_position = Vector2(50.0, 0.0)  # mid-radius: wave passes it partway through commit
	e._player_ref = hit_player
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var step := 0.02
	var elapsed := 0.0
	var got_hit := false
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
		if b.pending_hit_target == hit_player:
			got_hit = true
	assert_true(got_hit, "a player at mid-radius must be caught as the wave sweeps past them")

	var b2 := GroundSlamAbility.new(1.0, 0.1, 1.0, 0.1, 100.0, 20.0)
	var e2 := _MockEnemy.new()
	var far_player := _MockPlayer.new()
	far_player.global_position = Vector2(500.0, 0.0)  # well beyond the max radius
	e2._player_ref = far_player
	for _i in range(2):
		b2.tick(1.0, e2)
		if b2.wants_to_fire():
			b2.begin(e2)
			break
	elapsed = 0.0
	var never_hit := true
	while elapsed < b2.windup_duration() + b2.commit_duration() + 0.1:
		b2.tick(step, e2)
		elapsed += step
		if b2.pending_hit_target != null:
			never_hit = false
	assert_true(never_hit, "a player beyond the max radius must never be caught by the wave")


# --- 9. Fire-once ----------------------------------------------------------------

func test_damage_applied_exactly_once_across_whole_commit_window():
	var b := GroundSlamAbility.new(1.0, 0.1, 1.0, 0.1, 100.0, 40.0)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(50.0, 0.0)
	e._player_ref = p
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var hits := 0
	var step := 0.02
	var elapsed := 0.0
	while elapsed < b.windup_duration() + b.commit_duration() + 0.1:
		b.tick(step, e)
		elapsed += step
		if b.pending_hit_target != null:
			hits += 1
			b.pending_hit_target = null  # simulate the node consuming the handoff
	assert_eq(hits, 1, "the wave must damage a caught player exactly once per firing, not once per commit frame")


# --- 10. Escapable on foot --------------------------------------------------------

func test_walking_player_can_clear_the_ring_before_the_edge_reaches_max_radius():
	var b := GroundSlamAbility.new()
	var time_to_reach_edge: float = b.windup_duration() + b.commit_duration()
	var time_for_walker: float = b.max_radius() / 60.0
	assert_gt(time_to_reach_edge, time_for_walker,
		"a 60 px/s walker must be able to clear the ring before the wave reaches its max radius")


# --- 11. Edge cases ----------------------------------------------------------------

func test_idle_enemy_publishes_nothing():
	var b := GroundSlamAbility.new(1.0, 0.1, 0.5, 0.1)
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	for _i in range(5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "an IDLE enemy must not publish a ring zone")


func test_null_player_does_not_crash():
	var b := GroundSlamAbility.new(1.0, 0.1, 0.5, 0.1)
	var e := _MockEnemy.new()
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	for _i in range(20):
		b.tick(0.1, e)
	assert_null(b.pending_hit_target, "a null player reference must never resolve as hit")


func test_player_exactly_at_enemy_origin_is_caught_early():
	var b := GroundSlamAbility.new(1.0, 0.1, 0.5, 0.1)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2.ZERO
	e._player_ref = p
	for _i in range(2):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	b.tick(b.windup_duration() + 0.01, e)
	assert_eq(b.pending_hit_target, p,
		"a player standing exactly at the boss's feet must be caught as the wave begins")
