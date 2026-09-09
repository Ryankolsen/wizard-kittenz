extends GutTest

# Haunted Spray Bottle cone-spray migration (PRD #518 / issue #585). The last
# of the five standard mobs to move onto a shared archetype. The bottle now
# composes ConeSprayAbility (#576) unmodified for its fire cadence/telegraph;
# this file drives that composed ability directly through
# AbilityLoadout.haunted_spray_bottle_loadout(), the same shape
# test_cone_spray_ability.gd uses for Karaoke Karen, so the assertions here
# pin the bottle's own tuning (15deg half-angle, 2.0s cadence) rather than
# Karen's (35deg, 5.0s). Same _MockEnemy/_MockPlayer convention as every other
# per-kind ability test.

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref = null

class _MockPlayer extends Node2D:
	pass


func _make_ability() -> ConeSprayAbility:
	return AbilityLoadout.haunted_spray_bottle_loadout()[0]


# --- 3. Telegraph precedes the shot --------------------------------------------

func test_telegraph_precedes_the_shot():
	var b := _make_ability()
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	assert_not_null(b.active_zone, "a cone zone should be live once the cooldown elapses")
	assert_eq(b.active_zone.phase_at(b.zone_elapsed()), DangerZoneShape.Phase.WINDUP,
		"the zone must start in WINDUP, before any damage window opens")
	assert_null(b.pending_hit_target,
		"no hit may be produced while the zone is still in WINDUP")
	# Advance to just before commit begins — still must not have produced a hit.
	b.tick(b.windup_duration() - 0.01, e)
	assert_null(b.pending_hit_target,
		"no hit may be produced any time before the zone reaches COMMIT")
	assert_eq(b.active_zone.phase_at(b.zone_elapsed()), DangerZoneShape.Phase.WINDUP,
		"the zone must still be in WINDUP right up to the commit edge")


# --- 4. Flank --------------------------------------------------------------------

func test_flank_behind_the_bottle_during_windup_avoids_the_spray():
	var b := _make_ability()
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)  # ahead, so the cone locks facing east
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	# Player flanks behind the bottle during the wind-up.
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
	assert_false(hit, "a player who flanked behind the bottle during the wind-up must never be caught")


# --- 5. Wet debuff preserved -----------------------------------------------------

func test_wet_debuff_description_unchanged():
	var desc := HauntedSprayBottleBehavior.make_wet_description()
	assert_eq(desc.get("type_id"), PowerUpEffect.TYPE_WET,
		"wet description must still carry the wet type id")
	assert_eq(desc.get("duration"), 3.0,
		"wet duration must remain the pre-migration 3.0s")
	assert_eq(HauntedSprayBottleBehavior.WET_DURATION, 3.0,
		"WET_DURATION constant itself must remain 3.0s")


# --- 6. Float preserved -----------------------------------------------------------

func test_ignores_wall_collision_still_true():
	var b := HauntedSprayBottleBehavior.new()
	assert_true(b.ignores_wall_collision,
		"the bottle must still float over terrain post-migration")


# --- 7. Retire bespoke state -------------------------------------------------------

func test_pending_fire_aim_no_longer_exposed():
	var b := HauntedSprayBottleBehavior.new()
	var names := []
	for prop in b.get_property_list():
		names.append(prop.name)
	assert_false(names.has("pending_fire_aim"),
		"the retired bespoke fire cadence's pending_fire_aim must be gone")
	assert_false(names.has("pending_cone_origin"),
		"the retired bespoke fire cadence's pending_cone_origin must be gone")


# --- 8. Edge cases -------------------------------------------------------------------

func test_idle_bottle_publishes_nothing():
	var b := _make_ability()
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "an IDLE bottle must not publish a cone zone")


func test_player_exactly_at_bottle_position_is_caught():
	var b := _make_ability()
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(100.0, 0.0)  # locks facing east
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			break
	p.global_position = Vector2.ZERO  # stands exactly on the bottle at commit
	var elapsed := 0.0
	var step := 0.02
	var hit := false
	var total := b.windup_duration() + b.commit_duration() + 0.1
	while elapsed < total:
		b.tick(step, e)
		elapsed += step
		if b.pending_hit_target != null:
			hit = true
	assert_true(hit, "a player standing exactly on the bottle must be caught by the cone")


func test_null_player_does_not_crash():
	var b := _make_ability()
	var e := _MockEnemy.new()
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.pending_zone, "with no player reference the ability must never build a zone")
	for _i in range(20):
		b.tick(0.1, e)
	assert_null(b.pending_hit_target, "a null player reference must never resolve as hit")
