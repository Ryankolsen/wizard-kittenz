extends GutTest

# Warden Wretched (floor 10 / issue #580) -- composition-only slice combining
# the tracer slice's Pull archetype (#533) with Tyrone's zone-denial
# archetype (#571): hazards are laid first, then the pull drags the player
# across them. No archetype source changes here; only AbilityLoadout's
# tuning is under test. Reuses the same _MockEnemy/_MockPlayer shape as
# test_enemy_behavior.gd via preload, rather than redeclaring it, per the
# issue's instruction to use those mocks.

const _EnemyBehaviorTest = preload("res://tests/unit/test_enemy_behavior.gd")


func _mock_enemy():
	return _EnemyBehaviorTest._MockEnemy.new()


func _mock_player() -> Node2D:
	var p: Node2D = _EnemyBehaviorTest._MockPlayer.new()
	add_child_autofree(p)
	return p


func _split_loadout() -> Array:
	var pull: PullAbility = null
	var zone: ZoneDenialAbility = null
	for a in AbilityLoadout.warden_wretched_loadout():
		if a is PullAbility:
			pull = a
		elif a is ZoneDenialAbility:
			zone = a
	return [pull, zone]


# --- 3. Combination -----------------------------------------------------------

func test_hazard_is_alive_on_the_floor_when_the_pull_commits():
	var parts := _split_loadout()
	var pull: PullAbility = parts[0]
	var zone: ZoneDenialAbility = parts[1]
	assert_not_null(pull, "precondition: Warden's loadout must include a pull ability")
	assert_not_null(zone, "precondition: Warden's loadout must include a zone-denial ability")

	var e = _mock_enemy()
	var p := _mock_player()
	p.global_position = Vector2(150.0, 0.0)
	e._player_ref = p

	var step := 0.05
	var entered_commit := false
	var hazard_alive_at_commit := false
	for _i in range(1600):
		zone.tick(step, e)
		if zone.wants_to_fire():
			zone.begin(e)
		pull.tick(step, e)
		if pull.wants_to_fire():
			pull.begin(e)
		if pull.active_zone != null \
				and pull.active_zone.phase_at(pull.zone_elapsed()) == DangerZoneShape.Phase.COMMIT \
				and not entered_commit:
			entered_commit = true
			hazard_alive_at_commit = zone.alive_hazard_count() > 0
		if entered_commit:
			break
	assert_true(entered_commit, "the pull should have committed within the drive window")
	assert_true(hazard_alive_at_commit,
		"at least one hazard must be alive on the floor the moment the pull commits")


# --- 4. Counter preserved -------------------------------------------------------

func test_player_off_the_tether_line_is_not_pulled_even_with_hazards_present():
	var parts := _split_loadout()
	var pull: PullAbility = parts[0]
	var zone: ZoneDenialAbility = parts[1]

	var e = _mock_enemy()
	var p := _mock_player()
	p.global_position = Vector2(150.0, 0.0)
	e._player_ref = p

	# Let hazards accumulate first -- Warden's hazard cadence is short enough
	# that the floor is dotted with puddles well before the pull fires.
	var step := 0.05
	for _i in range(80):
		zone.tick(step, e)
		if zone.wants_to_fire():
			zone.begin(e)
	assert_gt(zone.alive_hazard_count(), 0,
		"precondition: at least one hazard should be laid before the pull fires")

	pull.begin(e)
	assert_not_null(pull.active_zone, "precondition: the pull must have telegraphed a tether")
	# Break the tether during the wind-up by stepping off the line.
	p.global_position = Vector2(150.0, pull.active_zone.width * 0.5 + 20.0)
	var position_at_break := p.global_position
	for _i in range(60):
		pull.tick(step, e)
	assert_null(pull.pending_pull_target,
		"a player who breaks the tether during wind-up must not be pulled, even with hazards on the floor")
	assert_eq(p.global_position, position_at_break,
		"the player's position must be unchanged when the tether is broken")


# --- 5. Escapable ---------------------------------------------------------------

func test_pull_windup_leaves_a_60px_walker_time_to_clear_the_tether_width():
	var parts := _split_loadout()
	var pull: PullAbility = parts[0]

	var e = _mock_enemy()
	var p := _mock_player()
	p.global_position = Vector2(150.0, 0.0)
	e._player_ref = p
	pull.begin(e)
	assert_not_null(pull.active_zone, "precondition: the pull must have telegraphed a tether")

	var walk_speed := 60.0
	var escape_distance: float = pull.active_zone.width * 0.5
	assert_gt(pull.windup_duration() * walk_speed, escape_distance * 2.0,
		"wind-up must leave at least double the margin needed to clear the tether")


# --- 6. Edge cases ---------------------------------------------------------------

func test_edge_player_on_the_enemy_does_not_crash_and_never_displaces_them_past_it():
	# PullAbility (unmodified, out of scope for this slice) has no zero-length
	# -heading guard the way TelegraphedChargeAbility does -- a player
	# standing exactly on the enemy still builds a degenerate zero-length
	# tether rather than refusing to fire. That is a pre-existing trait of
	# the shared archetype (equally true of the Vacuum's pull), not something
	# this composition introduces, so this pins the archetype's actual
	# contract instead: no crash, and the commit payload's own gap-clamp
	# never moves the caught player past the enemy.
	var parts := _split_loadout()
	var pull: PullAbility = parts[0]

	var e = _mock_enemy()
	e.global_position = Vector2(40.0, 40.0)
	var p := _mock_player()
	p.global_position = Vector2(40.0, 40.0)
	e._player_ref = p
	pull.begin(e)
	for _i in range(40):
		pull.tick(0.05, e)
	assert_eq(p.global_position, e.global_position,
		"a player caught at the enemy's own position must never end up past it")


func test_edge_pull_can_fire_before_any_hazard_has_been_laid():
	var parts := _split_loadout()
	var pull: PullAbility = parts[0]
	var zone: ZoneDenialAbility = parts[1]

	var e = _mock_enemy()
	var p := _mock_player()
	p.global_position = Vector2(150.0, 0.0)
	e._player_ref = p
	assert_eq(zone.alive_hazard_count(), 0, "precondition: no hazard laid yet")
	pull.begin(e)
	assert_not_null(pull.active_zone,
		"the pull must be able to fire even before any hazard has landed")


func test_edge_idle_warden_publishes_nothing_from_either_ability():
	var abilities := AbilityLoadout.warden_wretched_loadout()
	var e = _mock_enemy()
	e.state = 0  # EnemyAIState.State.IDLE
	var ceiling := 0
	for a in abilities:
		ceiling += int(ceil(a.cooldown())) + 2
	for _i in range(ceiling):
		for a in abilities:
			a.tick(1.0, e)
			if a.wants_to_fire():
				a.begin(e)
	for a in abilities:
		assert_null(a.active_zone,
			"an IDLE Warden Wretched must not produce a danger zone from either archetype")


func test_edge_null_player_ref_does_not_crash():
	var abilities := AbilityLoadout.warden_wretched_loadout()
	var e = _mock_enemy()
	for a in abilities:
		a.begin(e)
	assert_true(true, "beginning either archetype with no player ref must not crash")
