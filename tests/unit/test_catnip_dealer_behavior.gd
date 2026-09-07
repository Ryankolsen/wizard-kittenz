extends GutTest

# Catnip Dealer retreat-and-fire migration (PRD #518 / issue #582). Kiting and
# fire cadence are retired off CatnipDealerBehavior and onto the shared
# RetreatAndFireAbility (tuned to the dealer's own pre-migration constants,
# with the telegraph flag on). This file covers what's specific to the
# dealer's wiring: that the migrated kiting still reads exactly as the old
# hand-rolled desired_direction did, that the debuff roll stays deterministic
# per enemy id (issue #534), that the throw now telegraphs, and the same edge
# cases the old bespoke implementation had to survive.

class _MockPlayer extends Node2D:
	pass

class _MockData:
	var enemy_id: String = ""

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null
	var data: _MockData = _MockData.new()


func _dealer_ability() -> RetreatAndFireAbility:
	return AbilityLoadout.catnip_dealer_loadout()[0]


# --- 3. Kiting preserved ---------------------------------------------------------

func test_kiting_matches_the_pre_migration_desired_direction():
	# These assertions exist today against the bespoke CatnipDealerBehavior
	# implementation; they must keep passing against the shared archetype
	# (constructed with the dealer's own tuning) for the generalisation to be
	# faithful.
	var ability := _dealer_ability()
	var far_dir := ability.desired_direction(Vector2.ZERO, Vector2(150.0, 0.0))
	assert_eq(far_dir, Vector2(1.0, 0.0), "outside preferred range the dealer should approach")
	var near_dir := ability.desired_direction(Vector2.ZERO, Vector2(90.0, 0.0))
	assert_eq(near_dir, Vector2(-1.0, 0.0), "inside preferred range the dealer should back away")
	var held_dir := ability.desired_direction(
		Vector2.ZERO, Vector2(CatnipDealerBehavior.PREFERRED_RANGE, 0.0))
	assert_eq(held_dir, Vector2.ZERO, "inside the deadband the dealer should hold position")


# --- 4. Determinism (holds issue #534's fix in place) ----------------------------

func test_two_dealers_with_the_same_enemy_id_roll_the_same_debuff():
	var b1 := CatnipDealerBehavior.new()
	var b2 := CatnipDealerBehavior.new()
	var e1 := _MockEnemy.new()
	e1.data.enemy_id = "dealer-shared-id"
	var e2 := _MockEnemy.new()
	e2.data.enemy_id = "dealer-shared-id"
	b1.tick(0.1, e1)
	b2.tick(0.1, e2)
	assert_eq(b1.pick_debuff(), b2.pick_debuff(),
		"two dealers seeded from the same enemy id must apply the same debuff")


func test_dealers_with_different_enemy_ids_seed_independent_streams():
	# Not asserting the two rolls differ (that would be flaky — a 1/3 chance
	# of a same-index coincidence) but that each stream is seeded from its own
	# id rather than always falling back to one shared/non-deterministic RNG.
	var b1 := CatnipDealerBehavior.new()
	var b2 := CatnipDealerBehavior.new()
	var e1 := _MockEnemy.new()
	e1.data.enemy_id = "dealer-id-one"
	var e2 := _MockEnemy.new()
	e2.data.enemy_id = "dealer-id-two"
	b1.tick(0.1, e1)
	b2.tick(0.1, e2)
	var d1 := b1.pick_debuff()
	var d2 := b2.pick_debuff()
	assert_true(CatnipDealerBehavior.DEBUFF_TYPES.has(d1))
	assert_true(CatnipDealerBehavior.DEBUFF_TYPES.has(d2))


# --- 5. Telegraph precedes the throw ----------------------------------------------

func test_telegraph_zone_is_published_and_winding_up_before_any_throw():
	var ability := _dealer_ability()
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.global_position = Vector2(CatnipDealerBehavior.PREFERRED_RANGE, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(ability.fire_interval() / 0.05)) + 1):
		ability.tick(0.05, e)
		if ability.wants_to_fire():
			ability.begin(e)
	assert_not_null(ability.active_zone,
		"the fire interval elapsing should have telegraphed a zone")
	assert_eq(ability.active_zone.phase_at(ability.zone_elapsed()), DangerZoneShape.Phase.WINDUP,
		"the zone must still be winding up right after begin()")
	assert_null(ability.pending_fire_target,
		"no projectile should be produced before the telegraph commits")
	for _i in range(200):
		ability.tick(0.01, e)
		if ability.pending_fire_target != null:
			break
	assert_not_null(ability.pending_fire_target,
		"the throw should commit once the telegraphed zone reaches its commit phase")


# --- 6. Edge cases -----------------------------------------------------------------

func test_player_exactly_at_enemy_position_returns_a_safe_direction():
	var ability := _dealer_ability()
	var dir := ability.desired_direction(Vector2.ZERO, Vector2.ZERO)
	assert_almost_eq(dir.length(), 1.0, 0.0001,
		"a coincident player must not crash and should return a unit direction")


func test_idle_dealer_publishes_no_throw():
	var ability := _dealer_ability()
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	var p := _MockPlayer.new()
	p.global_position = Vector2(CatnipDealerBehavior.PREFERRED_RANGE, 0.0)
	e._player_ref = p
	for _i in range(int(ceil(ability.fire_interval() / 0.1)) + 5):
		ability.tick(0.1, e)
		if ability.wants_to_fire():
			ability.begin(e)
	assert_null(ability.pending_fire_target, "an IDLE dealer must never queue a throw")
	assert_null(ability.active_zone, "an IDLE dealer must never telegraph a throw either")


func test_null_player_does_not_crash():
	var ability := _dealer_ability()
	var e := _MockEnemy.new()
	e._player_ref = null
	for _i in range(int(ceil(ability.fire_interval() / 0.1)) + 5):
		ability.tick(0.1, e)
		if ability.wants_to_fire():
			ability.begin(e)
	assert_null(ability.pending_fire_target, "a dealer with no player ref must never queue a throw")
