extends GutTest

# Test subclass for the override-counter case (acceptance criterion 2).
class _CounterBehavior extends EnemyBehavior:
	var count: int = 0
	var last_delta: float = 0.0
	var last_enemy = null
	func tick(delta: float, enemy) -> void:
		count += 1
		last_delta = delta
		last_enemy = enemy


func test_base_tick_is_safe_no_op():
	# Acceptance #1: base interface is callable and does not crash.
	var b := EnemyBehavior.new()
	b.tick(0.1, null)
	assert_true(true, "base tick must not crash")


func test_subclass_can_override_tick():
	# Acceptance #2: subclasses override the hook and get the delta + enemy.
	var b := _CounterBehavior.new()
	var fake_enemy := RefCounted.new()
	b.tick(0.1, fake_enemy)
	b.tick(0.1, fake_enemy)
	b.tick(0.1, fake_enemy)
	assert_eq(b.count, 3, "tick override should have fired 3 times")
	assert_almost_eq(b.last_delta, 0.1, 0.0001)
	assert_eq(b.last_enemy, fake_enemy, "enemy arg should pass through")


func test_tick_with_null_enemy_is_safe():
	# Acceptance #4: null kind / missing enemy must not crash the tick path.
	var base := EnemyBehavior.new()
	base.tick(0.1, null)
	var sub := _CounterBehavior.new()
	sub.tick(0.1, null)
	assert_eq(sub.count, 1, "subclass tick with null enemy still increments")


func test_for_kind_returns_non_null_for_every_enum_value():
	# Acceptance #4 (factory side): the dispatch table is exhaustive over the
	# EnemyKind enum, so even kinds without a registered subclass yet return
	# the base no-op rather than null.
	for kind in EnemyData.EnemyKind.values():
		var b := EnemyBehavior.for_kind(kind)
		assert_not_null(b, "for_kind(%d) returned null" % kind)
		# Sanity-check the returned object is at least a base instance and
		# its tick is safe to call.
		b.tick(0.05, null)


func test_for_kind_returns_independent_instances():
	# Each call should mint a fresh instance so per-enemy state (cooldowns,
	# charge timers, projectile lists) doesn't leak across spawns.
	var a := EnemyBehavior.for_kind(EnemyData.EnemyKind.ANGRY_PIGEON)
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_ne(a, b, "for_kind should return distinct instances per call")


# ---------------------------------------------------------------------------
# AngryPigeonBehavior (issue #161) — dive-bomb charge state machine.
# ---------------------------------------------------------------------------

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null


# Bare Node2D stand-in used by aggro-gate tests that need a player reference
# attached to a mock enemy without dragging in PowerUpManager.
class _MockPlayer extends Node2D:
	pass

func test_angry_pigeon_charge_timer_counts_down():
	# Issue #161 acceptance #1: charge ~every 4 seconds. Driving four 1.0s
	# ticks against a mock without a player ref accrues the cooldown without
	# auto-triggering the charge — wants_to_charge flips true at the threshold.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	for _i in range(4):
		b.tick(1.0, e)
	assert_true(b.wants_to_charge(), "cooldown should have elapsed after 4 ticks of 1.0s")


func test_angry_pigeon_for_kind_dispatches_subclass():
	# The for_kind factory should hand back an AngryPigeonBehavior for the
	# ANGRY_PIGEON kind so the Enemy node's _ready wiring picks it up without
	# any per-kind branching at the call site.
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_true(b is AngryPigeonBehavior, "ANGRY_PIGEON kind must dispatch to AngryPigeonBehavior")


func test_angry_pigeon_begin_charge_locks_target():
	# Acceptance #2: charge locks a target position. begin_charge captures
	# the coord and flips is_charging so the next tick advances toward it.
	var b := AngryPigeonBehavior.new()
	var target := Vector2(200.0, 50.0)
	b.begin_charge(target)
	assert_eq(b.charge_target, target, "charge_target should match the position passed in")
	assert_true(b.is_charging, "is_charging should be true after begin_charge")
	assert_false(b.charge_completed, "charge_completed should be reset at charge start")


func test_angry_pigeon_charge_ends_on_arrival():
	# Acceptance #3: charge completes when the enemy reaches the target.
	# Drive ticks at a fixed delta and let the behavior step global_position
	# toward charge_target — the arrival check inside tick should flip
	# is_charging false once we're within ARRIVAL_DIST.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	e.global_position = Vector2.ZERO
	b.begin_charge(Vector2(120.0, 0.0))
	# CHARGE_SPEED=120 → 1.0s of travel covers the full 120 px in one tick.
	# Add a couple of extra ticks as a safety net against floating-point drift.
	for _i in range(3):
		b.tick(0.5, e)
		if not b.is_charging:
			break
	assert_false(b.is_charging, "charge should have ended after arrival")
	assert_true(b.charge_completed, "charge_completed should be set on arrival")
	assert_eq(e.global_position, Vector2(120.0, 0.0), "enemy should be snapped to target on completion")


func test_angry_pigeon_pending_hazard_position_set_on_completion():
	# Acceptance #4: on charge completion the impact point is published as
	# `pending_hazard_position` so the Enemy-side observer can spawn the
	# FloorHazard. The data handoff is what we test here; the scene-tree
	# spawn lives in the integration layer.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	var impact := Vector2(80.0, 80.0)
	b.begin_charge(impact)
	# One tick at 1.0s covers 120 px > 80*sqrt(2) ≈ 113 px, so arrival
	# triggers and pending_hazard_position should be the impact point.
	b.tick(1.0, e)
	assert_not_null(b.pending_hazard_position, "pending_hazard_position should be set after completion")
	assert_eq(b.pending_hazard_position, impact, "pending_hazard_position should equal the impact point")


func test_angry_pigeon_dead_enemy_skips_charge():
	# Acceptance #6: a dead pigeon must not accrue cooldown or begin a
	# charge — the DEAD state is the sink the rest of the AI honors.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	e.state = 3  # EnemyAIState.State.DEAD
	for _i in range(6):
		b.tick(1.0, e)
	assert_false(b.wants_to_charge(), "dead enemy should never want to charge")
	assert_false(b.is_charging, "dead enemy should never be charging")


# ---------------------------------------------------------------------------
# RogueRoombaBehavior (issue #162) — wall-bounce, damage trail, berserk.
# ---------------------------------------------------------------------------

class _MockRoombaData:
	var hp: int = 10
	var max_hp: int = 10
	var attack: int = 4
	var enemy_id: String = ""

class _MockRoombaEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var move_speed: float = 100.0
	var data: _MockRoombaData = _MockRoombaData.new()
	var _player_ref = null

func test_rogue_roomba_homes_toward_player():
	# Issue #262 acceptance #1: per-frame homing — desired_direction is a unit
	# vector from the roomba to the player's current position. Player at
	# (100, 0), roomba at (0, 0) → (1, 0).
	var b := RogueRoombaBehavior.new()
	var dir := b.desired_direction(Vector2.ZERO, Vector2(100, 0))
	assert_eq(dir, Vector2(1, 0), "homing direction should point at the player")

func test_rogue_roomba_resteers_after_player_moves():
	# Issue #262 acceptance #1: not a one-time aim. Moving the player produces
	# a fresh heading on the next call — proves the helper re-evaluates.
	var b := RogueRoombaBehavior.new()
	var first := b.desired_direction(Vector2.ZERO, Vector2(100, 0))
	var second := b.desired_direction(Vector2.ZERO, Vector2(0, 100))
	assert_eq(first, Vector2(1, 0), "initial heading right")
	assert_eq(second, Vector2(0, 1), "heading updates when player moves")

func test_rogue_roomba_no_longer_overrides_motion_with_bounce():
	# Issue #262 acceptance #2: the wall-bounce override path is gone. The
	# behavior must defer to the base _chase loop so per-frame homing happens
	# — `is_overriding_motion()` returns the EnemyBehavior default (false).
	var b := RogueRoombaBehavior.new()
	assert_false(b.is_overriding_motion(), "roomba no longer overrides base motion")


func test_rogue_roomba_for_kind_dispatches_subclass():
	# The for_kind factory should hand back a RogueRoombaBehavior for the
	# ROGUE_ROOMBA kind so Enemy._ready picks it up without per-kind branching.
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.ROGUE_ROOMBA)
	assert_true(b is RogueRoombaBehavior, "ROGUE_ROOMBA kind must dispatch to RogueRoombaBehavior")


# ---------------------------------------------------------------------------
# RogueRoombaBehavior migration onto zone-denial + enrage archetypes (PRD
# #518 / issue #584). The hand-rolled damage trail and one-shot berserk are
# retired in favor of the shared archetypes; this section covers the loadout
# wiring, the Vacuum-unaffected regression, and the tuning restated from the
# retired TRAIL_*/BERSERK_* constants (removed from RogueRoombaBehavior
# itself -- see AbilityLoadout.rogue_roomba_loadout's own comment for the
# retired values). Idle wander (desired_direction, idle_* tuning) is
# untouched and still tested above.
# ---------------------------------------------------------------------------

func test_rogue_roomba_loadout_resolves_to_exactly_zone_denial_and_enrage():
	# Test 1 (core wiring / loadout, issue #584): the standard (non-boss)
	# Rogue Roomba's kind resolves through AbilityLoadout.for_enemy to exactly
	# a ZoneDenialAbility and an EnrageAbility -- nothing else.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.ROGUE_ROOMBA, false)
	assert_eq(abilities.size(), 2, "the standard roomba's loadout must contain exactly two abilities")
	var has_zone_denial := false
	var has_enrage := false
	for ability in abilities:
		if ability is ZoneDenialAbility:
			has_zone_denial = true
		elif ability is EnrageAbility:
			has_enrage = true
		else:
			fail_test("the roomba's loadout must not contain any archetype besides zone denial and enrage")
	assert_true(has_zone_denial, "the standard roomba's loadout must include zone denial")
	assert_true(has_enrage, "the standard roomba's loadout must include enrage")


func test_rogue_roomba_migration_leaves_the_vacuum_untouched():
	# Test 2 (Vacuum unaffected, issue #584): the boss-tier ROGUE_ROOMBA is a
	# different loadout entirely (the Vacuum) sharing the same enum value --
	# AbilityLoadout.is_vacuum is the single authority for_enemy already
	# consults, but this asserts the concrete regression this slice is most
	# likely to cause directly, rather than only through the shared predicate.
	var vacuum_abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.ROGUE_ROOMBA, true)
	assert_eq(vacuum_abilities.size(), 2, "the Vacuum must still compose exactly two archetypes")
	assert_true(vacuum_abilities[0] is PullAbility, "the Vacuum's first archetype must still be Pull")
	assert_true(vacuum_abilities[1] is TelegraphedChargeAbility,
		"the Vacuum's second archetype must still be the telegraphed charge")


func test_rogue_roomba_zone_denial_and_enrage_tuning_restates_pre_migration_values():
	# Test 3 (tuning preserved, issue #584): the retired RogueRoombaBehavior
	# declared TRAIL_INTERVAL = 0.3, TRAIL_DURATION = 2.0,
	# TRAIL_DAMAGE_PER_SEC = 3.0, TRAIL_RADIUS = 20.0,
	# TRAIL_COLOR = Color(0.7, 0.4, 0.4, 0.4), BERSERK_HP_FRACTION = 0.3 and
	# BERSERK_SPEED_MULTIPLIER = 1.5. The migration must restate those numbers
	# on the composed archetypes, not retune them.
	var zone_denial: ZoneDenialAbility = null
	var enrage: EnrageAbility = null
	for a in AbilityLoadout.rogue_roomba_loadout():
		if a is ZoneDenialAbility:
			zone_denial = a
		elif a is EnrageAbility:
			enrage = a
	assert_not_null(zone_denial, "the roomba's loadout must include a zone-denial ability")
	assert_not_null(enrage, "the roomba's loadout must include an enrage ability")

	assert_almost_eq(zone_denial.cooldown(), 0.3, 0.0001,
		"zone-denial cooldown must restate the retired TRAIL_INTERVAL")
	assert_almost_eq(zone_denial.hazard_duration(), 2.0, 0.0001,
		"hazard duration must restate the retired TRAIL_DURATION")
	assert_almost_eq(zone_denial.hazard_damage_per_sec(), 3.0, 0.0001,
		"hazard damage per second must restate the retired TRAIL_DAMAGE_PER_SEC")
	assert_almost_eq(zone_denial.hazard_radius(), 20.0, 0.0001,
		"hazard radius must restate the retired TRAIL_RADIUS")
	assert_eq(zone_denial.hazard_color(), Color(0.7, 0.4, 0.4, 0.4),
		"hazard colour must restate the retired TRAIL_COLOR")

	assert_almost_eq(enrage.hp_fraction(), 0.3, 0.0001,
		"enrage threshold must restate the retired BERSERK_HP_FRACTION")
	assert_almost_eq(enrage.speed_multiplier(), 1.5, 0.0001,
		"enrage speed multiplier must restate the retired BERSERK_SPEED_MULTIPLIER")


func test_rogue_roomba_trail_telegraphs_before_the_hazard_persists():
	# The zone-denial disc is drawn (wind-up) before the hazard-spawn request
	# publishes on commit -- the whole point of migrating off the untelegraphed
	# hand-rolled trail (issue #584's motivating example).
	var zone_denial: ZoneDenialAbility = null
	for a in AbilityLoadout.rogue_roomba_loadout():
		if a is ZoneDenialAbility:
			zone_denial = a
	var e := _MockRoombaEnemy.new()
	e.data.enemy_id = "roomba-telegraph-1"
	for _i in range(int(ceil(zone_denial.cooldown())) + 5):
		zone_denial.tick(0.05, e)
		if zone_denial.wants_to_fire():
			zone_denial.begin(e)
			break
	assert_not_null(zone_denial.active_zone, "a firing must produce a telegraphed disc")
	assert_null(zone_denial.pending_hazard_spawn,
		"the hazard must not yet be requested during wind-up")
	var step := 0.01
	var elapsed := 0.0
	while elapsed < zone_denial.windup_duration() + 0.02:
		zone_denial.tick(step, e)
		elapsed += step
	assert_not_null(zone_denial.pending_hazard_spawn,
		"the hazard-spawn request must publish once wind-up ends")


func test_rogue_roomba_enrage_fires_once_and_never_refires_after_hp_recovery():
	# Test 4 (berserk semantics survive, issue #584): ports the retired
	# RogueRoombaBehavior berserk one-shot assertions onto the composed
	# EnrageAbility -- fires once at the threshold, never refires even after
	# HP recovers and drops again.
	var enrage: EnrageAbility = null
	for a in AbilityLoadout.rogue_roomba_loadout():
		if a is EnrageAbility:
			enrage = a
	var e := _MockRoombaEnemy.new()
	e.data.hp = 10
	e.data.max_hp = 10
	e.move_speed = 100.0
	enrage.tick(0.05, e)
	assert_false(enrage.has_enraged, "enrage must not fire while HP is above the threshold")
	e.data.hp = 3  # 30% of 10, exactly at the threshold
	enrage.tick(0.05, e)
	assert_true(enrage.has_enraged, "enrage must fire once HP falls to or below the threshold")
	assert_eq(enrage.enrage_entry_count, 1, "enrage entry counter should record exactly one entry")
	assert_almost_eq(e.move_speed, 150.0, 0.001,
		"speed must be multiplied by the retired BERSERK_SPEED_MULTIPLIER")
	e.data.hp = 10  # HP recovers back above the threshold
	enrage.tick(0.05, e)
	e.data.hp = 1  # and falls below the threshold again
	for _i in range(5):
		enrage.tick(0.05, e)
	assert_eq(enrage.enrage_entry_count, 1,
		"enrage must never refire, even after HP rises back above the threshold and falls again")
	assert_almost_eq(e.move_speed, 150.0, 0.001, "speed must not compound across subsequent ticks")


func test_rogue_roomba_no_longer_exposes_retired_berserk_and_trail_state():
	# Test 5 (retire bespoke state, issue #584): berserk_entry_count and
	# pending_trail_spawn must be gone from the behavior -- the enrage
	# archetype and zone-denial archetype own that state now.
	var b := RogueRoombaBehavior.new()
	assert_false("berserk_entry_count" in b, "berserk_entry_count must no longer exist on RogueRoombaBehavior")
	assert_false("pending_trail_spawn" in b, "pending_trail_spawn must no longer exist on RogueRoombaBehavior")
	assert_false("is_berserk" in b, "is_berserk must no longer exist on RogueRoombaBehavior")


func test_rogue_roomba_idle_enemy_lays_no_trail():
	# Test 6 (edge case, issue #584): an IDLE roomba must not accrue cooldown
	# or telegraph a trail hazard -- mirrors ZoneDenialAbility's own aggro
	# gate, exercised here through the roomba's specific tuning.
	var zone_denial: ZoneDenialAbility = null
	for a in AbilityLoadout.rogue_roomba_loadout():
		if a is ZoneDenialAbility:
			zone_denial = a
	var e := _MockRoombaEnemy.new()
	e.data.enemy_id = "roomba-idle-1"
	e.state = 0  # EnemyAIState.State.IDLE
	for _i in range(50):
		zone_denial.tick(0.1, e)
		if zone_denial.wants_to_fire():
			zone_denial.begin(e)
	assert_null(zone_denial.pending_zone, "an IDLE roomba must not publish a trail telegraph")
	assert_eq(zone_denial.alive_hazard_count(), 0, "an IDLE roomba must never accrue a live trail hazard")


func test_rogue_roomba_trail_hazard_cap_honored_under_dense_cadence():
	# Test 6 (edge case, issue #584): TRAIL_INTERVAL's dense 0.3s cadence must
	# still respect the archetype's alive-hazard cap (3, per
	# AbilityLoadout.rogue_roomba_loadout) rather than letting the floor fill
	# unbounded.
	var zone_denial: ZoneDenialAbility = null
	for a in AbilityLoadout.rogue_roomba_loadout():
		if a is ZoneDenialAbility:
			zone_denial = a
	var e := _MockRoombaEnemy.new()
	e.data.enemy_id = "roomba-cap-1"
	for _i in range(2000):
		zone_denial.tick(0.02, e)
		if zone_denial.wants_to_fire():
			zone_denial.begin(e)
		assert_true(zone_denial.alive_hazard_count() <= 3,
			"alive hazard count must never exceed the roomba's configured cap")


func test_rogue_roomba_null_player_does_not_crash():
	# Test 6 (edge case, issue #584): no _player_ref set on the mock enemy --
	# neither archetype needs a player target to fire (zone denial targets its
	# own position; enrage reads only HP), so ticking through many firings
	# with no player reference must not crash.
	var abilities := AbilityLoadout.rogue_roomba_loadout()
	var e := _MockRoombaEnemy.new()
	e.data.enemy_id = "roomba-null-player-1"
	e.data.hp = 1
	e.data.max_hp = 10
	for _i in range(50):
		for a in abilities:
			a.tick(0.1, e)
			if a.wants_to_fire():
				a.begin(e)
	assert_true(true, "ticking with no player reference must not crash")


# ---------------------------------------------------------------------------
# DogKnightBehavior (issue #163) — raised defense, drunk charge, mead drop.
# ---------------------------------------------------------------------------

class _MockDogEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null

func test_dog_knight_has_raised_base_defense():
	# Acceptance #1: DOG_KNIGHT base defense is strictly greater than all
	# other kinds. PRD #151 keeps the other four at the shared baseline;
	# DOG_KNIGHT is the documented exception.
	var dk := EnemyData.base_defense_for(EnemyData.EnemyKind.DOG_KNIGHT)
	for k in EnemyData.EnemyKind.values():
		if k == EnemyData.EnemyKind.DOG_KNIGHT:
			continue
		assert_gt(dk, EnemyData.base_defense_for(k),
			"DOG_KNIGHT defense should exceed kind %d" % k)


func test_dog_knight_mead_drop_on_death():
	# Acceptance #5: on_enemy_died publishes the death position as
	# pending_mead_drop_position so the Enemy-side observer can spawn the
	# mead PowerUpPickup. Data handoff only — scene spawn lives in Enemy.
	var b := DogKnightBehavior.new()
	var e := _MockDogEnemy.new()
	e.global_position = Vector2(50.0, 75.0)
	b.on_enemy_died(e)
	assert_not_null(b.pending_mead_drop_position,
		"pending_mead_drop_position should be set after on_enemy_died")
	assert_eq(b.pending_mead_drop_position, Vector2(50.0, 75.0),
		"pending_mead_drop_position should equal enemy.global_position")


func test_dog_knight_kill_reward_router_mead_hook():
	# Acceptance #6: KillRewardRouter exposes a static that returns the
	# mead pickup type for DOG_KNIGHT and "" for other kinds, so the
	# Enemy-side spawn-on-death wiring stays kind-agnostic.
	var dk := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	var ap := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_eq(KillRewardRouter.mead_drop_type_for(dk), PowerUpEffect.TYPE_ALE,
		"DOG_KNIGHT should drop a mead/ale pickup")
	assert_eq(KillRewardRouter.mead_drop_type_for(ap), "",
		"non-DOG_KNIGHT kinds should not drop mead")


func test_dog_knight_for_kind_dispatches_subclass():
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.DOG_KNIGHT)
	assert_true(b is DogKnightBehavior, "DOG_KNIGHT kind must dispatch to DogKnightBehavior")


func test_dog_knight_reports_pacer_idle_style_and_fraction():
	# PRD #391 / slice #393: the dog knight declares pacer wander at ~50% of
	# its chase speed (PRD mapping table). Drift here means the mob's idle
	# personality changed.
	var b := DogKnightBehavior.new()
	assert_eq(b.idle_style(), WanderProfile.Style.PACER,
		"dog knight should declare pacer style")
	assert_almost_eq(b.idle_speed_fraction(), 0.50, 0.0001,
		"dog knight should idle at ~50% of chase speed")


func test_dog_knight_idle_velocity_suppressed_while_charge_ability_is_dashing():
	# Ported from the pre-migration is_charging assertion (issue #581): the
	# behaviour idle motion is suppressed while the enemy is mid-commitment
	# is still true, now driven by the composed TelegraphedChargeAbility
	# rather than a behaviour-owned is_charging flag. is_overriding_motion is
	# EnemyBehavior's base aggregation over b.abilities, so wiring the ability
	# in is enough to prove the suppression still holds.
	var b := DogKnightBehavior.new()
	var ability = AbilityLoadout.dog_knight_loadout()[0]
	b.abilities = [ability]
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	var p: Node2D = autofree(Node2D.new())
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	ability.begin(e)
	# Advance into the commit phase (windup=1.0s), where is_overriding_motion
	# must be true.
	for _i in range(21):
		ability.tick(0.05, e)
	assert_true(b.is_overriding_motion(),
		"precondition: the committed charge should make is_overriding_motion true")
	for _i in range(5):
		var v: Vector2 = b.idle_velocity(e, 0.05)
		assert_eq(v, Vector2.ZERO,
			"idle velocity must be zero while the charge ability owns motion")


func test_dog_knight_dead_enemy_charge_ability_skips_charge():
	# Ported from the pre-migration wants_to_charge/is_charging assertion: a
	# dead dog knight must never wind up or commit a charge. DEAD is neither
	# CHASE nor ATTACK, so EnemyAbility's shared aggro gate (is_aggroed)
	# already blocks it — this pins that the migrated Dog Knight still gets
	# that guarantee through its composed ability.
	var ability = AbilityLoadout.dog_knight_loadout()[0]
	var e := _MockDogEnemy.new()
	e.state = 3  # DEAD
	for _i in range(6):
		ability.tick(1.0, e)
	assert_false(ability.wants_to_fire(), "a dead dog knight should never want to charge")
	assert_null(ability.active_zone, "a dead dog knight should never produce a charge lane")


# ---------------------------------------------------------------------------
# CatnipDealerBehavior (issue #164) — preferred range, flee, random debuff.
# ---------------------------------------------------------------------------

class _MockDealerPlayer extends Node2D:
	var data = null

class _MockDealerPlayerData:
	var hp: int = 10
	var max_hp: int = 10

class _MockDealerEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null


func test_catnip_dealer_pick_debuff_covers_all_three():
	# Acceptance #4: debuff selection eventually picks all three types.
	# 20 calls across a seeded RNG should yield at least one of each.
	var b := CatnipDealerBehavior.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var seen := {}
	for _i in range(20):
		seen[b.pick_debuff(rng)] = true
	assert_true(seen.has(CatnipDealerBehavior.DEBUFF_CONFUSION), "confusion should appear")
	assert_true(seen.has(CatnipDealerBehavior.DEBUFF_SLOWNESS), "slowness should appear")
	assert_true(seen.has(CatnipDealerBehavior.DEBUFF_MISFIRE), "misfire should appear")


func test_catnip_dealer_misfire_no_op_without_spells():
	# Acceptance #5: misfire against a bare player data with no spells must
	# not crash and must not mutate HP. Pure-data path — no SceneTree needed.
	var pd := _MockDealerPlayerData.new()
	pd.hp = 10
	CatnipDealerBehavior.apply_misfire(pd)
	assert_eq(pd.hp, 10, "misfire should not change HP")


func test_catnip_dealer_make_debuff_description_returns_type_id_and_duration():
	# PRD #284 Slice 2 test 5 — behavior seam returns a (type_id, duration)
	# description, NOT a PowerUpEffect. The manager handles construction via
	# the single apply path.
	var conf := CatnipDealerBehavior.make_debuff_description(
		CatnipDealerBehavior.DEBUFF_CONFUSION)
	assert_eq(conf.get("type_id"), PowerUpEffect.TYPE_CONFUSION,
		"confusion description carries the confusion type id")
	assert_eq(conf.get("duration"), CatnipDealerBehavior.DEBUFF_DURATION,
		"confusion description carries the tuned duration")
	var slow := CatnipDealerBehavior.make_debuff_description(
		CatnipDealerBehavior.DEBUFF_SLOWNESS)
	assert_eq(slow.get("type_id"), PowerUpEffect.TYPE_SLOWNESS,
		"slowness description carries the slowness type id")
	assert_eq(slow.get("duration"), CatnipDealerBehavior.DEBUFF_DURATION)
	# Misfire: empty Dictionary — no time-bounded state to push onto the manager.
	var misfire := CatnipDealerBehavior.make_debuff_description(
		CatnipDealerBehavior.DEBUFF_MISFIRE)
	assert_true(misfire.is_empty(),
		"misfire should not produce a debuff description")


func test_catnip_dealer_for_kind_dispatches_subclass():
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.CATNIP_DEALER)
	assert_true(b is CatnipDealerBehavior,
		"CATNIP_DEALER kind must dispatch to CatnipDealerBehavior")


# ---------------------------------------------------------------------------
# Catnip Dealer retreat-and-fire migration (PRD #518 / issue #582). Kiting and
# fire cadence move onto the shared RetreatAndFireAbility archetype; the
# bespoke desired_direction/wants_to_fire/pending_fire_target logic that used
# to live on CatnipDealerBehavior directly is retired in favor of it. The
# behavior keeps only what the archetype doesn't own: idle wander and the
# debuff-on-hit selection.
# ---------------------------------------------------------------------------

func test_catnip_dealer_loadout_is_exactly_one_retreat_and_fire():
	# Test 1 (core wiring / loadout): the Catnip Dealer's kind resolves through
	# AbilityLoadout.for_enemy to exactly one ability, a RetreatAndFireAbility.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.CATNIP_DEALER, false)
	assert_eq(abilities.size(), 1, "the Catnip Dealer composes exactly one archetype")
	assert_true(abilities[0] is RetreatAndFireAbility,
		"the Catnip Dealer's one archetype is retreat-and-fire")


func test_catnip_dealer_retreat_and_fire_tuning_restates_pre_migration_constants():
	# Test 2 (tuning preserved): preferred range, deadband and fire interval
	# must equal the pre-migration CatnipDealerBehavior constants, not new
	# numbers picked during the migration.
	var ability: RetreatAndFireAbility = AbilityLoadout.catnip_dealer_loadout()[0]
	assert_almost_eq(ability.preferred_range(), CatnipDealerBehavior.PREFERRED_RANGE, 0.0001,
		"preferred range must restate the retired CatnipDealerBehavior.PREFERRED_RANGE")
	assert_almost_eq(ability.range_deadband(), CatnipDealerBehavior.RANGE_DEADBAND, 0.0001,
		"deadband must restate the retired CatnipDealerBehavior.RANGE_DEADBAND")
	assert_almost_eq(ability.fire_interval(), CatnipDealerBehavior.FIRE_INTERVAL, 0.0001,
		"fire interval must restate the retired CatnipDealerBehavior.FIRE_INTERVAL")
	assert_true(ability.telegraph_enabled(),
		"the dealer opts into the telegraph the retired hand-rolled throw never had")


# ---------------------------------------------------------------------------
# HauntedSprayBottleBehavior (issue #165) — cone attack, Wet debuff, float.
# ---------------------------------------------------------------------------

class _MockSprayPlayer extends Node2D:
	var data = null
	var _manager: PowerUpManager = PowerUpManager.new()
	func apply_debuff(description: Dictionary) -> void:
		if description.is_empty():
			return
		var type_id: String = description.get("type_id", "")
		var duration: float = description.get("duration", -1.0)
		_manager.apply(type_id, data, duration)

class _MockSprayPlayerData:
	var speed: float = 100.0
	var hp: int = 10

class _MockSprayEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null


func test_haunted_spray_bottle_cone_spread_angles():
	# Acceptance #2 (tests #1): compute_cone_directions returns center + ±15°.
	var dirs := HauntedSprayBottleBehavior.compute_cone_directions(Vector2.RIGHT)
	assert_eq(dirs.size(), 3, "cone should yield 3 directions")
	assert_almost_eq(dirs[0].x, 1.0, 0.0001)
	assert_almost_eq(dirs[0].y, 0.0, 0.0001)
	var spread := deg_to_rad(HauntedSprayBottleBehavior.CONE_ANGLE_DEG)
	# Dot of two unit vectors at angle θ is cos(θ).
	assert_almost_eq(dirs[1].dot(Vector2.RIGHT), cos(spread), 0.0001)
	assert_almost_eq(dirs[2].dot(Vector2.RIGHT), cos(spread), 0.0001)
	# +15° rotates Vector2.RIGHT downward in Godot's y-down basis (sin(+θ) > 0).
	assert_true(dirs[1].y > 0.0, "first off-axis direction should be the +15° rotation")
	assert_true(dirs[2].y < 0.0, "second off-axis direction should be the -15° rotation")


func test_haunted_spray_bottle_fire_timer_fires():
	# Acceptance #2 (tests #2): wants_to_fire trips after ~2.0s.
	var b := HauntedSprayBottleBehavior.new()
	var e := _MockSprayEnemy.new()
	for _i in range(21):
		b.tick(0.1, e)
	assert_true(b.wants_to_fire(), "wants_to_fire should be true after 2.1s")


func test_haunted_spray_bottle_make_wet_description():
	# PRD #284 Slice 2 test 5 — seam returns a (type_id, duration) description,
	# not a WetEffect instance.
	var desc := HauntedSprayBottleBehavior.make_wet_description()
	assert_eq(desc.get("type_id"), PowerUpEffect.TYPE_WET,
		"wet description carries the wet type id")
	assert_eq(desc.get("duration"), HauntedSprayBottleBehavior.WET_DURATION,
		"wet description carries the spray bottle's tuned duration")


func test_haunted_spray_bottle_wet_effect_applied_on_hit():
	# Routed through the unified apply path: the wet description applied by the
	# manager mutates the target's speed (-30%).
	var pd := _MockSprayPlayerData.new()
	pd.speed = 100.0
	var manager := PowerUpManager.new()
	var desc := HauntedSprayBottleBehavior.make_wet_description()
	manager.apply(desc.type_id, pd, desc.duration)
	assert_almost_eq(pd.speed, 70.0, 0.0001, "speed should be reduced 30% while Wet")


func test_haunted_spray_bottle_wet_effect_refreshes_on_rehit():
	# A second hit while the first is still active refreshes the timer rather
	# than stacking another effect — same refresh-not-stack semantics whether
	# the description is applied once or many times.
	var pd := _MockSprayPlayerData.new()
	var manager := PowerUpManager.new()
	var desc := HauntedSprayBottleBehavior.make_wet_description()
	manager.apply(desc.type_id, pd, desc.duration)
	manager.tick(2.0)
	var active := manager.get_active(WetEffect.TYPE)
	assert_not_null(active, "WetEffect should still be active 2.0s in")
	assert_true(active.remaining < HauntedSprayBottleBehavior.WET_DURATION,
		"timer should have decayed before refresh")
	manager.apply(desc.type_id, pd, desc.duration)
	assert_almost_eq(active.remaining, HauntedSprayBottleBehavior.WET_DURATION, 0.0001,
		"re-hit should refresh remaining to the full WET_DURATION")
	assert_eq(manager.active_count(), 1, "refresh should not stack a second WetEffect")


func test_wall_mask_for_normal_behavior_sets_walls_bit():
	# Issue #263: normal kinds collide with dungeon wall tiles so move_and_slide
	# is blocked. The mask must include the dedicated walls bit.
	assert_eq(EnemyBehavior.wall_mask_for(EnemyBehavior.new()),
		EnemyBehavior.WALL_COLLISION_MASK,
		"default behavior must mask the walls bit")
	assert_eq(EnemyBehavior.wall_mask_for(AngryPigeonBehavior.new()),
		EnemyBehavior.WALL_COLLISION_MASK,
		"pigeon must mask the walls bit")
	assert_eq(EnemyBehavior.wall_mask_for(RogueRoombaBehavior.new()),
		EnemyBehavior.WALL_COLLISION_MASK,
		"roomba must mask the walls bit")


func test_wall_mask_for_haunted_spray_bottle_is_zero():
	# Issue #263 + #165: the spray bottle floats over terrain. Its mask must
	# stay clear of the walls bit so move_and_slide doesn't trap it.
	var b := HauntedSprayBottleBehavior.new()
	assert_true(b.ignores_wall_collision,
		"precondition: spray bottle declares ignores_wall_collision")
	assert_eq(EnemyBehavior.wall_mask_for(b), 0,
		"behaviors that ignore wall collision must return mask 0")


func test_player_masks_walls_by_default():
	# Issue #513: players default to wall-blocked, matching mob wall
	# collision. Phase-through is granted only via the Wall Walker
	# achievement (#512/#515).
	var scene: PackedScene = load("res://scenes/player.tscn")
	assert_not_null(scene, "player.tscn must load")
	var player := scene.instantiate() as CharacterBody2D
	add_child_autofree(player)
	assert_eq(player.collision_mask & EnemyBehavior.WALL_COLLISION_MASK, EnemyBehavior.WALL_COLLISION_MASK,
		"player CharacterBody2D must mask the dedicated walls bit by default")


func test_wall_collision_mask_uses_dedicated_bit_not_actor_bit():
	# Issue #263: the walls bit must not collide with the default actor layer
	# (bit 0). Players land on bit 0 by default, so masking only the walls bit
	# guarantees players are not blocked.
	assert_ne(EnemyBehavior.WALL_PHYSICS_LAYER_BIT, 0,
		"walls bit must not be the default actor bit (0)")
	assert_eq(EnemyBehavior.WALL_COLLISION_MASK,
		1 << EnemyBehavior.WALL_PHYSICS_LAYER_BIT,
		"WALL_COLLISION_MASK must be derived from WALL_PHYSICS_LAYER_BIT")


func test_haunted_spray_bottle_ignores_wall_collision_flag():
	# Acceptance #6 (tests #5): the float-over-terrain flag is on the behavior
	# itself so the Enemy node can clear collision_mask on _ready.
	var b := HauntedSprayBottleBehavior.new()
	assert_true(b.ignores_wall_collision,
		"spray bottle must declare it ignores wall collision")


func test_haunted_spray_bottle_for_kind_dispatches_subclass():
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE)
	assert_true(b is HauntedSprayBottleBehavior,
		"HAUNTED_SPRAY_BOTTLE kind must dispatch to HauntedSprayBottleBehavior")


func test_haunted_spray_bottle_dead_enemy_skips_fire():
	var b := HauntedSprayBottleBehavior.new()
	var e := _MockSprayEnemy.new()
	e.state = 3  # DEAD
	for _i in range(25):
		b.tick(0.1, e)
	assert_false(b.wants_to_fire(), "dead spray bottle should never want to fire")
	assert_eq(b.pending_fire_aim, null, "dead spray bottle should never queue a fire")


func test_haunted_spray_bottle_fire_publishes_aim_when_in_range():
	var b := HauntedSprayBottleBehavior.new()
	var e := _MockSprayEnemy.new()
	var p := _MockSprayPlayer.new()
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	for _i in range(21):
		b.tick(0.1, e)
	assert_not_null(b.pending_fire_aim,
		"fire should be queued once cooldown elapses and player ref is set")
	assert_almost_eq(b.pending_fire_aim.x, 1.0, 0.0001,
		"aim should point along the player vector")
	assert_almost_eq(b.pending_fire_aim.y, 0.0, 0.0001)
	assert_eq(b.pending_cone_origin, Vector2.ZERO,
		"cone origin should be the bottle's position at fire time")


func test_haunted_spray_bottle_preferred_range_hold():
	# Outside preferred range → approach; inside → back away.
	var b := HauntedSprayBottleBehavior.new()
	var far_dir := b.desired_direction(Vector2.ZERO, Vector2(140.0, 0.0))
	assert_eq(far_dir, Vector2(1.0, 0.0), "at 140px the bottle should approach")
	var near_dir := b.desired_direction(Vector2.ZERO, Vector2(70.0, 0.0))
	assert_eq(near_dir, Vector2(-1.0, 0.0), "at 70px the bottle should back away")


# ---------------------------------------------------------------------------
# Aggro gate (issue #261) — shared predicate + per-kind IDLE gating.
# ---------------------------------------------------------------------------

func test_aggro_gate_predicate():
	# Single source of truth: CHASE (1) / ATTACK (2) are aggroed; IDLE (0) /
	# DEAD (3) are not. Mirrors EnemyAIState.State exactly so every per-kind
	# special-ability gate reads the same boolean.
	var idle := _MockEnemy.new()
	idle.state = 0
	var chase := _MockEnemy.new()
	chase.state = 1
	var attack := _MockEnemy.new()
	attack.state = 2
	var dead := _MockEnemy.new()
	dead.state = 3
	assert_false(EnemyBehavior.is_aggroed(idle), "IDLE must not count as aggroed")
	assert_true(EnemyBehavior.is_aggroed(chase), "CHASE must count as aggroed")
	assert_true(EnemyBehavior.is_aggroed(attack), "ATTACK must count as aggroed")
	assert_false(EnemyBehavior.is_aggroed(dead), "DEAD must not count as aggroed")
	assert_false(EnemyBehavior.is_aggroed(null), "null enemy must not count as aggroed")


func test_angry_pigeon_idle_does_not_charge():
	# Cooldown elapses with a player ref present but state IDLE — the dive
	# must not initiate, and wants_to_charge must stay false because cooldown
	# never accrues outside aggro.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	var p := _MockPlayer.new()
	p.global_position = Vector2(40.0, 0.0)
	e._player_ref = p
	for _i in range(6):
		b.tick(1.0, e)
	assert_false(b.is_charging, "IDLE pigeon must not begin a dive bomb")
	assert_false(b.wants_to_charge(), "IDLE pigeon must not accrue charge cooldown")


func test_angry_pigeon_chase_still_charges():
	# Regression guard: with the gate in place, the existing CHASE-state path
	# still initiates the dive once cooldown elapses and a player ref is set.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	e.state = 1  # CHASE
	var p := _MockPlayer.new()
	p.global_position = Vector2(40.0, 0.0)
	e._player_ref = p
	# 4 ticks of 1.0s lands exactly on CHARGE_COOLDOWN; begin_charge fires on
	# tick 4 and a 5th tick would advance/complete the charge (player is only
	# 40px away vs. 120px/s step), so cap the loop short of completion.
	for _i in range(4):
		b.tick(1.0, e)
	assert_true(b.is_charging, "CHASE pigeon should still initiate dive after cooldown")


func test_angry_pigeon_committed_charge_completes_after_leaving_range():
	# Acceptance: a charge begun while aggroed completes even if the player
	# leaves detection range mid-dive. Begin charge in CHASE, flip to IDLE,
	# and the in-progress charge must still advance to completion.
	var b := AngryPigeonBehavior.new()
	var e := _MockEnemy.new()
	e.state = 1  # CHASE
	e.global_position = Vector2.ZERO
	b.begin_charge(Vector2(120.0, 0.0))
	e.state = 0  # IDLE — player left range mid-dive
	for _i in range(3):
		b.tick(0.5, e)
		if not b.is_charging:
			break
	assert_false(b.is_charging, "in-progress charge must complete even after de-aggro")
	assert_true(b.charge_completed, "charge_completed should be set on arrival")


func test_dog_knight_charge_ability_idle_does_not_charge():
	# Ported from the pre-migration behaviour-owned gate (issue #581): same
	# pattern as pigeon, now enforced by EnemyAbility's shared aggro gate
	# instead of a bespoke wants_to_charge on DogKnightBehavior.
	var ability = AbilityLoadout.dog_knight_loadout()[0]
	var e := _MockDogEnemy.new()
	e.state = 0  # IDLE
	for _i in range(6):
		ability.tick(1.0, e)
	assert_false(ability.wants_to_fire(), "IDLE dog must not accrue charge cooldown")
	assert_null(ability.active_zone, "IDLE dog must not begin a charge")


func test_dog_knight_charge_ability_chase_still_wants_charge():
	# Regression: cooldown still accrues in CHASE so the existing trigger fires.
	var ability = AbilityLoadout.dog_knight_loadout()[0]
	var e := _MockDogEnemy.new()
	e.state = 1  # CHASE
	for _i in range(5):
		ability.tick(1.0, e)
	assert_true(ability.wants_to_fire(), "CHASE dog should still want to charge after cooldown")


func test_spray_bottle_idle_does_not_fire():
	var b := HauntedSprayBottleBehavior.new()
	var e := _MockSprayEnemy.new()
	e.state = 0  # IDLE
	var p := _MockSprayPlayer.new()
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	for _i in range(25):
		b.tick(0.1, e)
	assert_eq(b.pending_fire_aim, null,
		"IDLE spray bottle must not queue a cone even with player in range")
	assert_false(b.wants_to_fire(),
		"IDLE spray bottle must not accrue fire cadence")


# ---------------------------------------------------------------------------
# Idle wander hooks (PRD #391 / slice #392) — HauntedSprayBottle stationary-ish.
# ---------------------------------------------------------------------------

class _MockIdleEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 0  # EnemyAIState.State.IDLE
	var move_speed: float = EnemyAIState.CHASE_SPEED
	var _player_ref: Node2D = null
	var data = null


class _MockIdleData:
	var enemy_id: String = "test-bottle-1"
	var spawn_position: Vector2 = Vector2.ZERO


func test_spray_bottle_reports_stationary_ish_idle_style_and_fraction():
	# Regression guard: the spray bottle declares stationary-ish wander at ~10%
	# of its chase speed. Drift here means the mob's idle personality changed.
	var b := HauntedSprayBottleBehavior.new()
	assert_eq(b.idle_style(), WanderProfile.Style.STATIONARY_ISH,
		"haunted spray bottle should declare stationary-ish style")
	assert_almost_eq(b.idle_speed_fraction(), 0.10, 0.0001,
		"haunted spray bottle should idle at ~10% of chase speed")


func test_spray_bottle_idle_velocity_returns_bounded_motion_in_idle():
	# Idle-velocity hook delegates to the profile module and returns a velocity
	# bounded by idle_speed. Over many ticks at least one is non-zero (the
	# stationary-ish shuffle fires) and none exceeds the bound.
	var b := HauntedSprayBottleBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	var idle_speed: float = e.move_speed * HauntedSprayBottleBehavior.IDLE_SPEED_FRACTION
	var any_nonzero := false
	for _i in range(500):
		var v: Vector2 = b.idle_velocity(e, 0.05)
		assert_true(v.length() <= idle_speed + 0.0001,
			"idle velocity should stay bounded by idle_speed")
		if v.length() > 0.0:
			any_nonzero = true
	assert_true(any_nonzero,
		"idle-velocity hook should produce some non-zero motion over time")


func test_spray_bottle_idle_velocity_is_zero_when_aggroed():
	# Aggro takeover: when state is CHASE, the idle path returns Vector2.ZERO
	# so it can't fight the base _chase loop. Same for ATTACK and DEAD.
	var b := HauntedSprayBottleBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	for s in [EnemyAIState.State.CHASE, EnemyAIState.State.ATTACK,
			EnemyAIState.State.DEAD]:
		e.state = s
		for _i in range(20):
			var v: Vector2 = b.idle_velocity(e, 0.05)
			assert_eq(v, Vector2.ZERO,
				"idle velocity must be zero outside IDLE state (state=%d)" % s)


func test_rogue_roomba_reports_restless_idle_style_and_fraction():
	# PRD #391 / slice #394: roomba declares restless wander at ~60% of chase
	# speed — the most active idle mob (PRD mapping table). Drift here means
	# the mob's idle personality changed.
	var b := RogueRoombaBehavior.new()
	assert_eq(b.idle_style(), WanderProfile.Style.RESTLESS,
		"rogue roomba should declare restless style")
	assert_almost_eq(b.idle_speed_fraction(), 0.60, 0.0001,
		"rogue roomba should idle at ~60% of chase speed")


func test_rogue_roomba_idle_velocity_produces_motion_in_idle():
	# Restless wander runs in IDLE: over many ticks the hook produces non-zero
	# motion bounded by idle_speed (chase_speed * 0.60).
	var b := RogueRoombaBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	var idle_speed: float = e.move_speed * RogueRoombaBehavior.IDLE_SPEED_FRACTION
	var any_nonzero := false
	for _i in range(200):
		var v: Vector2 = b.idle_velocity(e, 0.05)
		assert_true(v.length() <= idle_speed + 0.0001,
			"idle velocity should stay bounded by idle_speed")
		if v.length() > 0.0:
			any_nonzero = true
	assert_true(any_nonzero,
		"restless idle hook should produce non-zero motion over time")


func test_rogue_roomba_idle_velocity_is_zero_when_aggroed():
	# Aggro takeover: chase/attack/dead all suppress the idle path so it can't
	# fight the base _chase loop or animate after death.
	var b := RogueRoombaBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	for s in [EnemyAIState.State.CHASE, EnemyAIState.State.ATTACK,
			EnemyAIState.State.DEAD]:
		e.state = s
		for _i in range(20):
			var v: Vector2 = b.idle_velocity(e, 0.05)
			assert_eq(v, Vector2.ZERO,
				"idle velocity must be zero outside IDLE state (state=%d)" % s)


func test_angry_pigeon_reports_pacer_idle_style_and_fraction():
	# PRD #391 (retuned): pigeon declares pacer at ~35% of chase speed, sharing
	# the same pacer path tuning as the catnip dealer.
	var b := AngryPigeonBehavior.new()
	assert_eq(b.idle_style(), WanderProfile.Style.PACER,
		"angry pigeon should declare pacer style")
	assert_almost_eq(b.idle_speed_fraction(), 0.35, 0.0001,
		"angry pigeon should idle at ~35% of chase speed")


func test_angry_pigeon_idle_velocity_produces_motion_in_idle():
	var b := AngryPigeonBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	var idle_speed: float = e.move_speed * AngryPigeonBehavior.IDLE_SPEED_FRACTION
	var any_nonzero := false
	for _i in range(200):
		var v: Vector2 = b.idle_velocity(e, 0.05)
		assert_true(v.length() <= idle_speed + 0.0001,
			"idle velocity should stay bounded by idle_speed")
		if v.length() > 0.0:
			any_nonzero = true
	assert_true(any_nonzero,
		"pacer idle hook should produce non-zero motion over time")


func test_angry_pigeon_idle_velocity_suppressed_during_dive():
	# Edge case #4: when the pigeon is mid-dive (is_overriding_motion true), the
	# idle pacer path must not drive motion — the dive owns global_position.
	var b := AngryPigeonBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	b.begin_charge(Vector2(200.0, 0.0))
	assert_true(b.is_overriding_motion(),
		"precondition: dive should make is_overriding_motion true")
	for _i in range(20):
		var v: Vector2 = b.idle_velocity(e, 0.05)
		assert_eq(v, Vector2.ZERO,
			"idle velocity must be zero while dive override is active")


func test_angry_pigeon_idle_velocity_is_zero_when_aggroed():
	var b := AngryPigeonBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	for s in [EnemyAIState.State.CHASE, EnemyAIState.State.ATTACK,
			EnemyAIState.State.DEAD]:
		e.state = s
		for _i in range(20):
			var v: Vector2 = b.idle_velocity(e, 0.05)
			assert_eq(v, Vector2.ZERO,
				"idle velocity must be zero outside IDLE state (state=%d)" % s)


func test_catnip_dealer_reports_pacer_idle_style_and_fraction():
	# PRD #391 (retuned): the dealer declares pacer at ~35% of chase speed,
	# sharing the same pacer path tuning as the angry pigeon. Drift here means
	# the mob's idle personality changed.
	var b := CatnipDealerBehavior.new()
	assert_eq(b.idle_style(), WanderProfile.Style.PACER,
		"catnip dealer should declare pacer style")
	assert_almost_eq(b.idle_speed_fraction(), 0.35, 0.0001,
		"catnip dealer should idle at ~35% of chase speed")


func test_catnip_dealer_idle_velocity_returns_bounded_motion_in_idle():
	# Idle-velocity hook delegates to the profile module and stays bounded by
	# idle_speed. Over many ticks at least one sample is non-zero (the dealer's
	# small drift fires) and none exceeds the bound.
	var b := CatnipDealerBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	var idle_speed: float = e.move_speed * CatnipDealerBehavior.IDLE_SPEED_FRACTION
	var any_nonzero := false
	for _i in range(500):
		var v: Vector2 = b.idle_velocity(e, 0.05)
		assert_true(v.length() <= idle_speed + 0.0001,
			"idle velocity should stay bounded by idle_speed")
		if v.length() > 0.0:
			any_nonzero = true
	assert_true(any_nonzero,
		"pacer idle hook should produce some non-zero motion over time")


func test_catnip_dealer_idle_velocity_is_zero_when_aggroed():
	# Aggro takeover: CHASE/ATTACK/DEAD all suppress the idle path so it can't
	# fight the base _chase loop or animate after death.
	var b := CatnipDealerBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	for s in [EnemyAIState.State.CHASE, EnemyAIState.State.ATTACK,
			EnemyAIState.State.DEAD]:
		e.state = s
		for _i in range(20):
			var v: Vector2 = b.idle_velocity(e, 0.05)
			assert_eq(v, Vector2.ZERO,
				"idle velocity must be zero outside IDLE state (state=%d)" % s)


# ---------------------------------------------------------------------------
# PRD #391 mapping table regression guard — all five kinds in one place so
# drift in any kind's idle personality breaks one obvious test.
# ---------------------------------------------------------------------------

func test_full_idle_mapping_table_regression_guard():
	# Anti-drift guard for PRD #391 §Solution: every kind's (style, idle-speed
	# fraction) pair is asserted in one place so silent retunes are caught.
	var expected := [
		{
			"kind": EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE,
			"style": WanderProfile.Style.STATIONARY_ISH,
			"fraction": 0.10,
			"label": "haunted spray bottle",
		},
		{
			"kind": EnemyData.EnemyKind.CATNIP_DEALER,
			"style": WanderProfile.Style.PACER,
			"fraction": 0.35,
			"label": "catnip dealer",
		},
		{
			"kind": EnemyData.EnemyKind.ANGRY_PIGEON,
			"style": WanderProfile.Style.PACER,
			"fraction": 0.35,
			"label": "angry pigeon",
		},
		{
			"kind": EnemyData.EnemyKind.DOG_KNIGHT,
			"style": WanderProfile.Style.PACER,
			"fraction": 0.50,
			"label": "dog knight",
		},
		{
			"kind": EnemyData.EnemyKind.ROGUE_ROOMBA,
			"style": WanderProfile.Style.RESTLESS,
			"fraction": 0.60,
			"label": "rogue roomba",
		},
	]
	for row in expected:
		var b := EnemyBehavior.for_kind(row.kind)
		assert_eq(b.idle_style(), row.style,
			"%s should declare style %d" % [row.label, row.style])
		assert_almost_eq(b.idle_speed_fraction(), row.fraction, 0.0001,
			"%s idle fraction should be %f" % [row.label, row.fraction])


func test_idle_velocity_pulls_displaced_mob_back_toward_anchor():
	# Edge case — resume-in-place after aggro loss. A mob displaced from its
	# spawn anchor and dropped back to IDLE must drift home rather than snap.
	# The wander module's leash kicks in past the radius and overrides velocity
	# with a vector pointed at the anchor — drives the "meander home, no snap"
	# behavior from PRD #391 §Implementation Decisions.
	var b := CatnipDealerBehavior.new()
	var e := _MockIdleEnemy.new()
	var d := _MockIdleData.new()
	# Non-zero spawn so _resolve_anchor picks up the spawn point (the falsy-zero
	# guard treats Vector2.ZERO as unset for legacy fixtures).
	var anchor := Vector2(500.0, 500.0)
	d.spawn_position = anchor
	e.data = d
	e.state = EnemyAIState.State.IDLE
	# Drop the mob well past the leash radius along +X from the anchor so the
	# leash branch dominates regardless of which phase the RNG happened on.
	var displaced := anchor + Vector2(CatnipDealerBehavior.IDLE_RADIUS * 4.0, 0.0)
	e.global_position = displaced
	var v: Vector2 = b.idle_velocity(e, 0.05)
	assert_true(v.x < 0.0,
		"displaced mob's idle velocity should point back toward the anchor (got %s)" % v)
	# Snap-home would teleport global_position to the anchor on the IDLE drop;
	# the leash never mutates position directly — only the velocity does.
	assert_eq(e.global_position, displaced,
		"idle velocity must not snap-teleport the mob home")


func test_spray_bottle_chase_still_fires():
	var b := HauntedSprayBottleBehavior.new()
	var e := _MockSprayEnemy.new()
	e.state = 1  # CHASE
	var p := _MockSprayPlayer.new()
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	for _i in range(21):
		b.tick(0.1, e)
	assert_not_null(b.pending_fire_aim,
		"CHASE spray bottle should still queue a cone after cooldown")


# ---------------------------------------------------------------------------
# Ability loadout + boss routing (PRD #518 / tracer slice #533).
# ---------------------------------------------------------------------------

func test_loadout_is_non_empty_for_every_enemy_kind():
	# Acceptance #9: the loadout table is exhaustive over EnemyKind, the same
	# contract for_kind already holds. Kinds whose archetype conversion is a
	# later issue (#534-#545) still answer with their existing behavior rather
	# than an empty list, so the generic pump never has nothing to drive.
	for kind in EnemyData.EnemyKind.values():
		var abilities := AbilityLoadout.for_enemy(kind, false)
		assert_false(abilities.is_empty(), "loadout for kind %d must not be empty" % kind)


func test_vacuum_loadout_is_pull_plus_telegraphed_charge():
	# Acceptance #9 (Vacuum): the floor-1 boss composes exactly the two
	# archetypes the PRD assigns it. BossRoster maps floor 1 to the Vacuum,
	# whose kind is ROGUE_ROOMBA — the is_boss flag is what separates the boss
	# loadout from the standard roomba's.
	var vacuum := BossRoster.boss_for_floor(1)
	var abilities := AbilityLoadout.for_enemy(vacuum.kind, true)
	assert_eq(abilities.size(), 2, "the Vacuum composes exactly two archetypes")
	assert_true(abilities[0] is PullAbility, "the Vacuum's first archetype is Pull")
	assert_true(abilities[1] is TelegraphedChargeAbility,
		"the Vacuum's second archetype is the telegraphed charge")


func test_boss_no_longer_resolves_to_a_bare_base_behavior():
	# Acceptance #10: the is_boss branch forcing EnemyBehavior.new() is gone.
	# The floor-1 boss resolves to its own behavior with a real loadout.
	var vacuum := BossRoster.boss_for_floor(1)
	var data := EnemyData.make_new(vacuum.kind)
	data.is_boss = true
	var b := EnemyBehavior.for_data(data)
	assert_false(
		b.get_script() == EnemyBehavior.new().get_script(),
		"a boss must not resolve to a bare base EnemyBehavior")
	assert_eq(b.abilities.size(), 2, "the Vacuum's behavior carries its two archetypes")


func test_sir_pickleton_loadout_is_ambush_plus_telegraphed_charge():
	# Loadout test (issue #536): Sir Pickleton composes exactly its two named
	# archetypes — ambush/petrify plus the telegraphed charge it falls back to
	# when a scare fails to land.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.SIR_PICKLETON, true)
	assert_eq(abilities.size(), 2, "Sir Pickleton composes exactly two archetypes")
	assert_true(abilities[0] is AmbushAbility, "Sir Pickleton's first archetype is Ambush/Petrify")
	assert_true(abilities[1] is TelegraphedChargeAbility,
		"Sir Pickleton's second archetype is the telegraphed charge")


func test_old_lady_pearl_loadout_is_summon_plus_retreat_and_fire():
	# Loadout test (issue #537): Old Lady Pearl composes exactly her two named
	# archetypes — spawns adds on a cooldown, and kites/fires while the player
	# is at range.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.OLD_LADY_PEARL, true)
	assert_eq(abilities.size(), 2, "Old Lady Pearl composes exactly two archetypes")
	assert_true(abilities[0] is SummonAddsAbility, "Old Lady Pearl's first archetype is Summon adds")
	assert_true(abilities[1] is RetreatAndFireAbility,
		"Old Lady Pearl's second archetype is Retreat and fire")


# ---------------------------------------------------------------------------
# Dog Knight telegraphed-charge migration (PRD #518 / issue #581). The one
# standard-mob special players reliably notice — kept at its original cadence
# and speed, re-expressed in the shared amber-to-red lane.
# ---------------------------------------------------------------------------

func test_dog_knight_loadout_is_exactly_one_telegraphed_charge():
	# Test 1 (core wiring / loadout): mirrors the Pickleton/Pearl loadout
	# assertions above. The Dog Knight's kind resolves through
	# AbilityLoadout.for_enemy to exactly one ability, a TelegraphedChargeAbility.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.DOG_KNIGHT, false)
	assert_eq(abilities.size(), 1, "the Dog Knight composes exactly one archetype")
	assert_true(abilities[0] is TelegraphedChargeAbility,
		"the Dog Knight's one archetype is the telegraphed charge")


func test_dog_knight_charge_tuning_restates_the_pre_migration_values():
	# Test 2 (tuning preserved): the retired DogKnightBehavior declared
	# CHARGE_COOLDOWN = 5.0 and CHARGE_SPEED = 140.0 px/s sustained over its
	# CHARGE_DURATION = 1.0s charge. The migration must restate those numbers,
	# not retune them.
	var ability: TelegraphedChargeAbility = AbilityLoadout.dog_knight_loadout()[0]
	assert_almost_eq(ability.cooldown(), 5.0, 0.0001,
		"charge cooldown must restate the retired CHARGE_COOLDOWN")
	assert_almost_eq(ability.commit_duration(), 1.0, 0.0001,
		"commit duration must restate the retired CHARGE_DURATION")
	assert_almost_eq(ability.lane_width(), 48.0, 0.0001,
		"lane width should be the tuning this migration commits to")

	# Dash speed has no dedicated field — TelegraphedChargeAbility.drive_motion
	# paces the dash as lane_length / commit_duration — so measure it directly:
	# fire the charge and see how far the enemy actually travels over the
	# whole commit window.
	var e := _MockDogEnemy.new()
	e.global_position = Vector2.ZERO
	var p: Node2D = autofree(Node2D.new())
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	ability.begin(e)
	# Advance to the end of the 1.0s wind-up (commit has not started yet),
	# driving motion each tick the same way the Enemy node's ability pump
	# does (tick, then drive_motion while the ability owns motion). Small
	# 0.01s steps keep discretization error well under the assert tolerance.
	for _i in range(100):
		ability.tick(0.01, e)
		if ability.is_overriding_motion():
			ability.drive_motion(0.01, e)
	var commit_start_position: Vector2 = e.global_position
	# Advance across the full 1.0s commit window.
	for _i in range(100):
		ability.tick(0.01, e)
		if ability.is_overriding_motion():
			ability.drive_motion(0.01, e)
	var travelled := e.global_position.distance_to(commit_start_position)
	assert_almost_eq(travelled / ability.commit_duration(), 140.0, 2.0,
		"dash speed (distance travelled / commit_duration) must restate CHARGE_SPEED")


func test_dog_knight_charge_zone_is_the_hitbox():
	# Test 3 (zone is the hitbox): a player standing on the lane at commit is
	# hit; the same player offset beyond the half-width is not. Mirrors
	# test_player_standing_in_the_lane_is_hit_once_at_commit /
	# test_player_who_walks_clear_of_the_lane_takes_no_damage in
	# test_enemy_ability.gd.
	var ability: TelegraphedChargeAbility = AbilityLoadout.dog_knight_loadout()[0]
	var e := _MockDogEnemy.new()
	var p: Node2D = autofree(Node2D.new())
	p.global_position = Vector2(100.0, 0.0)
	e._player_ref = p
	ability.begin(e)
	for _i in range(60):
		ability.tick(0.05, e)
	assert_eq(ability.pending_hit_target, p,
		"a player standing in the drawn lane must be hit when the charge commits")

	var ability2: TelegraphedChargeAbility = AbilityLoadout.dog_knight_loadout()[0]
	var e2 := _MockDogEnemy.new()
	var p2: Node2D = autofree(Node2D.new())
	p2.global_position = Vector2(100.0, 0.0)
	e2._player_ref = p2
	ability2.begin(e2)
	p2.global_position = Vector2(100.0, ability2.lane_width() * 0.5 + 20.0)
	for _i in range(60):
		ability2.tick(0.05, e2)
	assert_null(ability2.pending_hit_target,
		"a player outside the drawn lane's half-width must not be hit")


func test_dog_knight_charge_idle_enemy_publishes_no_zone():
	# Test 4 (edge case, aggro gate): an IDLE dog knight must not telegraph.
	var ability: TelegraphedChargeAbility = AbilityLoadout.dog_knight_loadout()[0]
	var e := _MockDogEnemy.new()
	e.state = 0  # IDLE
	for _i in range(10):
		ability.tick(1.0, e)
	assert_null(ability.active_zone, "an IDLE Dog Knight must not produce a danger zone")


func test_dog_knight_charge_null_player_does_not_crash():
	# Test 4 (edge case): no _player_ref set — begin must not crash and must
	# not produce a zone (there is nothing to aim it at).
	var ability: TelegraphedChargeAbility = AbilityLoadout.dog_knight_loadout()[0]
	var e := _MockDogEnemy.new()
	ability.begin(e)
	assert_null(ability.active_zone, "a charge with no player target must not produce a zone")


func test_dog_knight_charge_zero_length_heading_does_not_produce_a_degenerate_lane():
	# Test 4 (edge case): the player standing exactly on the enemy's own
	# position gives a zero-length heading; _build_zone must refuse rather
	# than construct a degenerate zero-length lane.
	var ability: TelegraphedChargeAbility = AbilityLoadout.dog_knight_loadout()[0]
	var e := _MockDogEnemy.new()
	e.global_position = Vector2(40.0, 40.0)
	var p: Node2D = autofree(Node2D.new())
	p.global_position = Vector2(40.0, 40.0)
	e._player_ref = p
	ability.begin(e)
	assert_null(ability.active_zone,
		"a zero-length heading must not produce a degenerate lane")


func test_is_vacuum_predicate_is_true_only_for_boss_rogue_roomba():
	# Issue #567 test 1 (core wiring): the thinnest statement that one authority
	# exists for "the boss-tier Rogue Roomba is the Vacuum".
	assert_true(AbilityLoadout.is_vacuum(EnemyData.EnemyKind.ROGUE_ROOMBA, true),
		"boss-flagged ROGUE_ROOMBA must be the Vacuum")
	assert_false(AbilityLoadout.is_vacuum(EnemyData.EnemyKind.ROGUE_ROOMBA, false),
		"non-boss ROGUE_ROOMBA must not be the Vacuum")


func test_is_vacuum_predicate_governs_loadout_content():
	# Issue #567 test 2 (content details): the behaviour the refactor must
	# preserve. Boss-flagged ROGUE_ROOMBA gets exactly Pull + telegraphed
	# charge; the standard roomba does not.
	var vacuum_abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.ROGUE_ROOMBA, true)
	assert_eq(vacuum_abilities.size(), 2, "the Vacuum composes exactly two archetypes")
	assert_true(vacuum_abilities[0] is PullAbility, "the Vacuum's first archetype is Pull")
	assert_true(vacuum_abilities[1] is TelegraphedChargeAbility,
		"the Vacuum's second archetype is the telegraphed charge")

	var standard_abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.ROGUE_ROOMBA, false)
	var has_pull := false
	var has_charge := false
	for a in standard_abilities:
		if a is PullAbility:
			has_pull = true
		if a is TelegraphedChargeAbility:
			has_charge = true
	assert_false(has_pull, "the standard roomba must not get Pull")
	assert_false(has_charge, "the standard roomba must not get the telegraphed charge")


func test_is_vacuum_predicate_agrees_with_for_kind_dispatch():
	# Issue #567 test 3 (agreement across sites): EnemyBehavior.for_kind must
	# return a VacuumBossBehavior for exactly the case the predicate calls the
	# Vacuum — the two authorities cannot disagree.
	for kind in EnemyData.EnemyKind.values():
		for is_boss in [true, false]:
			var b := EnemyBehavior.for_kind(kind, is_boss)
			var expected_vacuum := AbilityLoadout.is_vacuum(kind, is_boss)
			assert_eq(b is VacuumBossBehavior, expected_vacuum,
				"for_kind(%d, %s) VacuumBossBehavior-ness must match is_vacuum" % [kind, is_boss])


func test_is_vacuum_predicate_is_false_for_every_other_kind_and_out_of_range():
	# Issue #567 test 4 (edge cases): every other EnemyKind answers false at
	# both is_boss settings, and an out-of-range kind integer answers false
	# without crashing.
	for kind in EnemyData.EnemyKind.values():
		if kind == EnemyData.EnemyKind.ROGUE_ROOMBA:
			continue
		assert_false(AbilityLoadout.is_vacuum(kind, true),
			"kind %d with is_boss=true must not be the Vacuum" % kind)
		assert_false(AbilityLoadout.is_vacuum(kind, false),
			"kind %d with is_boss=false must not be the Vacuum" % kind)
	assert_false(AbilityLoadout.is_vacuum(9999, true),
		"an out-of-range kind integer must answer false without crashing")
	assert_false(AbilityLoadout.is_vacuum(-1, false),
		"a negative out-of-range kind integer must answer false without crashing")


func test_boss_routes_through_the_same_factory_as_standard_mobs():
	# Acceptance #10 (routing): boss-ness no longer short-circuits the factory,
	# so a boss of a kind with a registered subclass gets that subclass.
	var data := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	data.is_boss = true
	var b := EnemyBehavior.for_data(data)
	assert_true(b is DogKnightBehavior,
		"is_boss must not divert a kind away from its registered behavior")


# ---------------------------------------------------------------------------
# Co-op RNG determinism (issue #534 / PRD #518 "Co-op consistency"). Enemy AI
# runs locally on every client and only death is synchronised, so a behavior
# that randomises at construction makes each client fight a visibly different
# enemy. Behavior RNG is seeded from the enemy's stable spawn id, which is
# already derived from the shared dungeon seed, so every client rolls the same
# sequence without a single new network packet.
# ---------------------------------------------------------------------------

class _MockSeededData:
	var enemy_id: String = ""
	var spawn_position: Vector2 = Vector2.ZERO

class _MockSeededEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null
	var data = _MockSeededData.new()


# Mock enemy carrying `enemy_id`; pass null to model a spawn whose data is
# missing entirely (pre-spawn-layer fixtures, the legacy static enemy).
func _seeded_enemy(enemy_id) -> _MockSeededEnemy:
	var e := _MockSeededEnemy.new()
	if enemy_id == null:
		e.data = null
	else:
		e.data.enemy_id = enemy_id
	return e


func test_catnip_dealer_same_enemy_id_picks_the_same_debuff():
	# Acceptance #2 (content details): the catnip bag must apply the same
	# debuff on every client, and it must still be one of the three declared
	# types rather than whatever the seeding happens to produce.
	var b_client_a := CatnipDealerBehavior.new()
	var b_client_b := CatnipDealerBehavior.new()
	b_client_a.tick(0.1, _seeded_enemy("f3-r2-e4"))
	b_client_b.tick(0.1, _seeded_enemy("f3-r2-e4"))
	var debuff_a: String = b_client_a.pick_debuff()
	assert_eq(debuff_a, b_client_b.pick_debuff(),
		"same enemy_id must apply the same debuff on every client")
	assert_true(CatnipDealerBehavior.DEBUFF_TYPES.has(debuff_a),
		"the seeded pick must still be one of the three declared debuff types")


func test_catnip_dealer_seeded_debuff_sequence_is_stable():
	# Acceptance #4 (sequence stability) on the content side: a dealer that
	# fires repeatedly stays in sync for every bag, not only the first.
	var b_client_a := CatnipDealerBehavior.new()
	var b_client_b := CatnipDealerBehavior.new()
	b_client_a.tick(0.1, _seeded_enemy("f3-r2-e9"))
	b_client_b.tick(0.1, _seeded_enemy("f3-r2-e9"))
	b_client_a.pick_debuff()
	b_client_b.pick_debuff()
	assert_eq(b_client_a.pick_debuff(), b_client_b.pick_debuff(),
		"second debuff roll should match across clients")
	assert_eq(b_client_a.pick_debuff(), b_client_b.pick_debuff(),
		"third debuff roll should match across clients")


func test_catnip_dealer_with_null_data_ticks_safely():
	# Acceptance #5 (edge case) on the content side.
	var b := CatnipDealerBehavior.new()
	b.tick(0.1, _seeded_enemy(null))
	assert_true(CatnipDealerBehavior.DEBUFF_TYPES.has(b.pick_debuff()),
		"a null-data dealer should still pick a declared debuff type")


# ---------------------------------------------------------------------------
# Trash Panda Tyrone / zone-denial + steal archetypes (PRD #518 / issues
# #571 + #572). Complete as of #572: the disc plus the gold theft.
# ---------------------------------------------------------------------------

func test_trash_panda_tyrone_loadout_resolves_to_exactly_steal_and_zone_denial():
	# Test 9 (loadout, issue #572): Trash Panda Tyrone's kind resolves through
	# AbilityLoadout.for_enemy to exactly a StealAbility and a
	# ZoneDenialAbility — nothing else.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.TRASH_PANDA_TYRONE, false)
	assert_eq(abilities.size(), 2, "Tyrone's loadout must contain exactly two abilities")
	var has_zone_denial := false
	var has_steal := false
	for ability in abilities:
		if ability is ZoneDenialAbility:
			has_zone_denial = true
		elif ability is StealAbility:
			has_steal = true
		else:
			fail_test("Tyrone's loadout must not contain any archetype besides steal and zone denial")
	assert_true(has_zone_denial, "Trash Panda Tyrone's loadout must include zone denial")
	assert_true(has_steal, "Trash Panda Tyrone's loadout must include steal")


# ---------------------------------------------------------------------------
# Big Bruiser Buster / ground-slam + knockback-shove archetypes (PRD #518 /
# issues #573 + #574). Complete: ground slam teaches "get outside the ring"
# and knockback shove teaches "don't stand in his face".
# ---------------------------------------------------------------------------

func test_big_bruiser_buster_loadout_is_exactly_ground_slam_and_knockback_shove():
	# Test 8 (loadout, issue #574): mirrors the Pickleton/Pearl/Tyrone loadout
	# assertions above. Big Bruiser Buster's kind resolves through
	# AbilityLoadout.for_enemy to exactly a GroundSlamAbility and a
	# KnockbackShoveAbility — nothing else.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.BIG_BRUISER_BUSTER, false)
	var has_ground_slam := false
	var has_knockback_shove := false
	for ability in abilities:
		if ability is GroundSlamAbility:
			has_ground_slam = true
		elif ability is KnockbackShoveAbility:
			has_knockback_shove = true
		else:
			fail_test("Buster's loadout must not contain any archetype besides ground slam and knockback shove")
	assert_true(has_ground_slam, "Big Bruiser Buster's loadout must include ground slam")
	assert_true(has_knockback_shove, "Big Bruiser Buster's loadout must include knockback shove")


# ---------------------------------------------------------------------------
# Last Call Larry / zone-denial + enrage archetypes (PRD #518 / issue #575).
# Zone denial is Tyrone's archetype reused with tighter tuning (see
# test_zone_denial_ability.gd's second-consumer test); enrage is new here.
# ---------------------------------------------------------------------------

func test_last_call_larry_loadout_resolves_to_exactly_zone_denial_and_enrage():
	# Test 7 (loadout, issue #575): mirrors the Pickleton/Pearl/Tyrone/Buster
	# loadout assertions above. Last Call Larry's kind resolves through
	# AbilityLoadout.for_enemy to exactly a ZoneDenialAbility and an
	# EnrageAbility -- nothing else.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.LAST_CALL_LARRY, true)
	assert_eq(abilities.size(), 2, "Larry's loadout must contain exactly two abilities")
	var has_zone_denial := false
	var has_enrage := false
	for ability in abilities:
		if ability is ZoneDenialAbility:
			has_zone_denial = true
		elif ability is EnrageAbility:
			has_enrage = true
		else:
			fail_test("Larry's loadout must not contain any archetype besides zone denial and enrage")
	assert_true(has_zone_denial, "Last Call Larry's loadout must include zone denial")
	assert_true(has_enrage, "Last Call Larry's loadout must include enrage")


func test_enrage_is_confined_to_the_two_allowed_boss_kinds():
	# Test 8 (roster constraint, issue #575). The PRD is explicit that a
	# universal rage state was considered and rejected -- enrage is
	# deliberately restricted to exactly two bosses across the whole roster,
	# Last Call Larry and DJ Dubstep, so a later slice can't quietly hand it
	# to a third.
	#
	# Sequencing note: DJ Dubstep's own enrage slice is issue #579, a
	# separate, not-yet-built issue blocked behind this one -- so at the
	# point this issue lands, Larry is genuinely the *only* boss with enrage
	# in his loadout, not two. Asserting a literal "exactly two" here today
	# would fail until #579 lands, and there is currently no other enrage
	# user anywhere in AbilityLoadout to make two true. The interim
	# assertion below is worded to hold both now (one user: Larry) and after
	# #579 lands (two users: Larry + Dubstep) without needing to change --
	# it names the closed allowlist {Larry, Dubstep} the roster's enrage
	# users must stay a subset of (the scarcity rule this test exists to
	# hold), and separately requires Larry present today. It does *not*
	# assert Dubstep's absence, so #579 flips this from "one of two allowed"
	# to "two of two allowed" with zero edits to this test.
	var enrage_kinds: Array = []
	for floor_number in range(1, BossRoster.roster_size() + 1):
		var info := BossRoster.boss_for_floor(floor_number)
		var abilities := AbilityLoadout.for_enemy(info.kind, true)
		var has_enrage := false
		for ability in abilities:
			if ability is EnrageAbility:
				has_enrage = true
		if has_enrage:
			enrage_kinds.append(info.kind)
	var allowed := [EnemyData.EnemyKind.LAST_CALL_LARRY, EnemyData.EnemyKind.DJ_DUBSTEP]
	for kind in enrage_kinds:
		assert_true(allowed.has(kind),
			"enrage must never be handed to a boss kind besides Last Call Larry or DJ Dubstep")
	assert_true(enrage_kinds.has(EnemyData.EnemyKind.LAST_CALL_LARRY),
		"Last Call Larry must carry enrage")
	assert_lte(enrage_kinds.size(), 2,
		"enrage must never be carried by more than the two allowed boss kinds")


# ---------------------------------------------------------------------------
# DJ Dubstep / beat-locked slam + enrage archetypes (PRD #518 / issue #579).
# ---------------------------------------------------------------------------

func test_dj_dubstep_loadout_resolves_to_exactly_beat_locked_slam_and_enrage():
	# Test 9 (loadout, issue #579): mirrors the Pickleton/Pearl/Tyrone/Buster/
	# Larry loadout assertions above. DJ Dubstep's kind resolves through
	# AbilityLoadout.for_enemy to exactly a BeatLockedSlamAbility and an
	# EnrageAbility -- nothing else.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.DJ_DUBSTEP, true)
	assert_eq(abilities.size(), 2, "Dubstep's loadout must contain exactly two abilities")
	var has_beat_locked_slam := false
	var has_enrage := false
	for ability in abilities:
		if ability is BeatLockedSlamAbility:
			has_beat_locked_slam = true
		elif ability is EnrageAbility:
			has_enrage = true
		else:
			fail_test("Dubstep's loadout must not contain any archetype besides beat-locked slam and enrage")
	assert_true(has_beat_locked_slam, "DJ Dubstep's loadout must include the beat-locked slam")
	assert_true(has_enrage, "DJ Dubstep's loadout must include enrage")


func test_enrage_is_confined_to_exactly_larry_and_dubstep():
	# Test 10 (roster constraint, issue #579). Now that Dubstep's slice has
	# landed, the interim "at most two, Larry present" assertion above tightens
	# into the literal closed pair the PRD names: enrage belongs to Larry and
	# Dubstep, and to exactly those two -- no more, no fewer.
	var enrage_kinds: Array = []
	for floor_number in range(1, BossRoster.roster_size() + 1):
		var info := BossRoster.boss_for_floor(floor_number)
		var abilities := AbilityLoadout.for_enemy(info.kind, true)
		var has_enrage := false
		for ability in abilities:
			if ability is EnrageAbility:
				has_enrage = true
		if has_enrage:
			enrage_kinds.append(info.kind)
	assert_eq(enrage_kinds.size(), 2,
		"exactly two boss kinds across the roster must include enrage")
	assert_true(enrage_kinds.has(EnemyData.EnemyKind.LAST_CALL_LARRY),
		"Last Call Larry must carry enrage")
	assert_true(enrage_kinds.has(EnemyData.EnemyKind.DJ_DUBSTEP),
		"DJ Dubstep must carry enrage")


# ---------------------------------------------------------------------------
# Warden Wretched / pull + zone-denial composition (PRD #518 / issue #580).
# Both archetypes already exist -- pull from the tracer slice (#533), zone
# denial from Tyrone's slice (#571) -- so this loadout is composition and
# tuning only, no new archetype code.
# ---------------------------------------------------------------------------

func test_warden_wretched_loadout_resolves_to_exactly_pull_and_zone_denial():
	# Test 1 (core wiring / loadout): mirrors the Pickleton/Pearl/Tyrone/
	# Buster/Larry loadout assertions above. Warden Wretched's kind resolves
	# through AbilityLoadout.for_enemy to exactly a PullAbility and a
	# ZoneDenialAbility -- nothing else.
	var abilities := AbilityLoadout.for_enemy(EnemyData.EnemyKind.WARDEN_WRETCHED, true)
	assert_eq(abilities.size(), 2, "Warden Wretched's loadout must contain exactly two abilities")
	var has_pull := false
	var has_zone_denial := false
	for ability in abilities:
		if ability is PullAbility:
			has_pull = true
		elif ability is ZoneDenialAbility:
			has_zone_denial = true
		else:
			fail_test("Warden Wretched's loadout must not contain any archetype besides pull and zone denial")
	assert_true(has_pull, "Warden Wretched's loadout must include pull")
	assert_true(has_zone_denial, "Warden Wretched's loadout must include zone denial")


func test_warden_wretched_pull_reach_differs_from_vacuum_and_hazard_cadence_differs_from_tyrone():
	# Test 2 (tuning distinct): proves the loadout table is doing the
	# differentiating rather than a shared default -- Warden's pull reach
	# must differ from the Vacuum's, and his hazard cadence must differ from
	# Tyrone's.
	var warden_pull: PullAbility = null
	var warden_zone: ZoneDenialAbility = null
	for a in AbilityLoadout.warden_wretched_loadout():
		if a is PullAbility:
			warden_pull = a
		elif a is ZoneDenialAbility:
			warden_zone = a
	assert_not_null(warden_pull, "Warden Wretched's loadout must include a pull ability")
	assert_not_null(warden_zone, "Warden Wretched's loadout must include a zone-denial ability")

	# Measure reach by aiming each pull at a target far beyond any plausible
	# cap and reading the tether length _build_zone actually produced
	# (clamped to that ability's own max_reach) -- no private field access
	# needed.
	var vacuum_pull: PullAbility = AbilityLoadout.vacuum_loadout()[0]
	var far_target := Vector2(100000.0, 0.0)

	var e_warden := _MockEnemy.new()
	var p_warden := _MockPlayer.new()
	add_child_autofree(p_warden)
	p_warden.global_position = far_target
	e_warden._player_ref = p_warden
	warden_pull.begin(e_warden)
	var warden_reach: float = warden_pull.active_zone.length

	var e_vacuum := _MockEnemy.new()
	var p_vacuum := _MockPlayer.new()
	add_child_autofree(p_vacuum)
	p_vacuum.global_position = far_target
	e_vacuum._player_ref = p_vacuum
	vacuum_pull.begin(e_vacuum)
	var vacuum_reach: float = vacuum_pull.active_zone.length

	assert_ne(warden_reach, vacuum_reach, "Warden's pull reach must differ from the Vacuum's")

	var tyrone_zone: ZoneDenialAbility = null
	for a in AbilityLoadout.trash_panda_tyrone_loadout():
		if a is ZoneDenialAbility:
			tyrone_zone = a
	assert_ne(warden_zone.cooldown(), tyrone_zone.cooldown(),
		"Warden's hazard cadence must differ from Tyrone's")
