extends GutTest

# ZoneDenialAbility (PRD #518 / issue #571). Drops persistent FloorHazard
# discs to deny space; the player's counter is spacing and not getting
# cornered. Same _MockEnemy/_MockPlayer shape as test_enemy_behavior.gd, and
# the same seeded-mock pattern as test_summon_adds_ability.gd (issue #534's
# determinism scheme).

class _MockData:
	var enemy_id: String = ""

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var data: _MockData = _MockData.new()
	var _player_ref = null

class _MockPlayer extends Node2D:
	pass


func _seeded(enemy_id: String) -> _MockEnemy:
	var e := _MockEnemy.new()
	e.data.enemy_id = enemy_id
	return e


# --- 5. Core wiring ----------------------------------------------------------

func test_disc_zone_published_after_cooldown_when_aggroed():
	var b := ZoneDenialAbility.new()
	var e := _seeded("f4-r1-e0")
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_not_null(b.pending_zone, "a disc zone should have been published once the cooldown elapsed")
	assert_eq(b.pending_zone.kind, DangerZoneShape.Kind.DISC,
		"zone denial's telegraph must be a disc, not a lane/tether")


# --- 6. Hazard on commit -----------------------------------------------------

func test_hazard_spawn_requested_exactly_once_per_firing():
	var b := ZoneDenialAbility.new()
	var e := _seeded("f4-r1-e1")
	# Drive past cooldown and begin the firing.
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	var zone_origin: Vector2 = b.active_zone.origin
	# Advance through wind-up into commit.
	var step := 0.05
	var elapsed := 0.0
	while elapsed < b.windup_duration() + 0.01:
		b.tick(step, e)
		elapsed += step
	assert_not_null(b.pending_hazard_spawn, "a hazard-spawn request must publish on the commit frame")
	assert_eq(b.pending_hazard_spawn, zone_origin,
		"the hazard must spawn at the committed zone's own origin")
	b.pending_hazard_spawn = null
	# Several further commit-window frames must not publish a second request.
	for _i in range(5):
		b.tick(step, e)
		assert_null(b.pending_hazard_spawn,
			"a hazard-spawn request must publish once per firing, not once per commit frame")


# --- 7. Cap -------------------------------------------------------------------

func test_alive_hazard_count_never_exceeds_the_cap():
	var b := ZoneDenialAbility.new(1.0, 0.1, 0.1, 0.1, 32.0, 2.0, 0.3, 3.0, 32.0, Color.WHITE, 2)
	var e := _seeded("f4-r2-e0")
	for _i in range(400):
		b.tick(0.5, e)
		if b.wants_to_fire():
			b.begin(e)
		assert_true(b.alive_hazard_count() <= 2,
			"alive hazard count must never exceed the cap, got %d" % b.alive_hazard_count())


# --- 8. Determinism -----------------------------------------------------------

func test_same_enemy_id_produces_identical_hazard_positions():
	var a := ZoneDenialAbility.new()
	var b := ZoneDenialAbility.new()
	var origin_a := a.roll_zone_origin(_seeded("f4-r3-e5"))
	var origin_b := b.roll_zone_origin(_seeded("f4-r3-e5"))
	assert_eq(origin_a, origin_b, "same enemy_id must roll the identical hazard position")


func test_different_enemy_ids_are_able_to_differ():
	var differs := false
	for i in range(5):
		var a := ZoneDenialAbility.new()
		var b := ZoneDenialAbility.new()
		var origin_a := a.roll_zone_origin(_seeded("f4-r3-e%d-x" % i))
		var origin_b := b.roll_zone_origin(_seeded("f4-r3-e%d-y" % i))
		if origin_a != origin_b:
			differs = true
			break
	assert_true(differs, "different enemy_ids must not roll identical hazard positions")


# --- 9. Edge cases -------------------------------------------------------------

func test_idle_enemy_publishes_nothing():
	var b := ZoneDenialAbility.new()
	var e := _seeded("f4-r4-e0")
	e.state = 0  # IDLE
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "an IDLE enemy must not publish a disc zone")


func test_dead_enemy_publishes_nothing():
	var b := ZoneDenialAbility.new()
	var e := _seeded("f4-r4-e1")
	e.state = 3  # DEAD
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "a DEAD enemy must not publish a disc zone")


func test_null_enemy_does_not_crash():
	var b := ZoneDenialAbility.new()
	b.tick(1.0, null)
	assert_true(true, "tick with a null enemy must not crash")


# --- 6. Second consumer (Last Call Larry, PRD #518 / issue #575) -------------
# Larry reuses this archetype unchanged -- his difference is tuning only, so
# the floor genuinely closes in as the fight goes on: puddles land more often
# and linger longer than Tyrone's.

func test_larry_zone_denial_is_more_frequent_and_longer_lived_than_tyrones():
	var tyrone_ability: ZoneDenialAbility = null
	for a in AbilityLoadout.trash_panda_tyrone_loadout():
		if a is ZoneDenialAbility:
			tyrone_ability = a
	var larry_ability: ZoneDenialAbility = null
	for a in AbilityLoadout.larry_loadout():
		if a is ZoneDenialAbility:
			larry_ability = a
	assert_not_null(tyrone_ability, "Tyrone's loadout must include a zone-denial ability")
	assert_not_null(larry_ability, "Larry's loadout must include a zone-denial ability")
	assert_lt(larry_ability.cooldown(), tyrone_ability.cooldown(),
		"Larry's puddles must spawn on a shorter interval than Tyrone's")
	assert_gt(larry_ability.hazard_duration(), tyrone_ability.hazard_duration(),
		"Larry's puddles must linger longer than Tyrone's")
	# The hazard cap is tracked per-instance -- driving Tyrone's copy full
	# must not affect Larry's independent count. Checked right after a
	# firing (not after the whole drive loop), since a hazard decays back
	# out on its own duration and the loop otherwise risks landing on a gap
	# between one hazard expiring and the next firing.
	var e := _seeded("f6-r1-e0")
	var tyrone_ever_had_a_hazard := false
	for _i in range(400):
		tyrone_ability.tick(0.5, e)
		if tyrone_ability.wants_to_fire():
			tyrone_ability.begin(e)
		if tyrone_ability.alive_hazard_count() > 0:
			tyrone_ever_had_a_hazard = true
	assert_true(tyrone_ever_had_a_hazard,
		"sanity: Tyrone's ability should have accrued some alive hazards")
	assert_eq(larry_ability.alive_hazard_count(), 0,
		"Larry's hazard cap/count must be tracked independently of Tyrone's")
