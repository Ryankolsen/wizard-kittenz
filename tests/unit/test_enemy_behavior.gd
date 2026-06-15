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

class _MockRoombaEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var data: _MockRoombaData = _MockRoombaData.new()

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


func test_rogue_roomba_trail_timer_fires_periodically():
	# Acceptance #2: a trail segment is requested every ~0.3s while moving.
	# After 0.35s of ticks the behavior should set pending_trail_spawn; the
	# observer consumes it by clearing the flag back to false.
	var b := RogueRoombaBehavior.new()
	var e := _MockRoombaEnemy.new()
	b.tick(0.35, e)
	assert_true(b.pending_trail_spawn, "trail spawn should be requested after 0.35s")
	# Observer-side consumption.
	b.pending_trail_spawn = false
	b.tick(0.35, e)
	assert_true(b.pending_trail_spawn, "second trail spawn should fire 0.35s later")


func test_rogue_roomba_berserk_triggers_at_threshold():
	# Acceptance #4: at ≤30% HP berserk activates. 3/10 HP = 30% — equal-to
	# the threshold should trigger.
	var b := RogueRoombaBehavior.new()
	var e := _MockRoombaEnemy.new()
	e.data.hp = 3
	e.data.max_hp = 10
	b.tick(0.05, e)
	assert_true(b.is_berserk, "berserk should activate at ≤30% HP")
	assert_eq(b.berserk_entry_count, 1, "berserk entry counter should record one entry")


func test_rogue_roomba_berserk_fires_once_per_encounter():
	# Acceptance #6: berserk entry fires exactly once even if HP drops further.
	# The observer applies tint / speed / FloatingText off berserk_entry_count
	# crossing 0→1, so re-firing on subsequent ticks would double-apply the buff.
	var b := RogueRoombaBehavior.new()
	var e := _MockRoombaEnemy.new()
	e.data.hp = 3
	e.data.max_hp = 10
	b.tick(0.05, e)
	e.data.hp = 1
	for _i in range(5):
		b.tick(0.05, e)
	assert_eq(b.berserk_entry_count, 1, "berserk should fire exactly once per encounter")


func test_rogue_roomba_no_berserk_above_threshold():
	# Acceptance: 50% HP is above the 30% threshold — no berserk.
	var b := RogueRoombaBehavior.new()
	var e := _MockRoombaEnemy.new()
	e.data.hp = 5
	e.data.max_hp = 10
	b.tick(0.05, e)
	assert_false(b.is_berserk, "berserk should not activate above 30% HP")
	assert_eq(b.berserk_entry_count, 0, "no berserk entry above threshold")


func test_rogue_roomba_for_kind_dispatches_subclass():
	# The for_kind factory should hand back a RogueRoombaBehavior for the
	# ROGUE_ROOMBA kind so Enemy._ready picks it up without per-kind branching.
	var b := EnemyBehavior.for_kind(EnemyData.EnemyKind.ROGUE_ROOMBA)
	assert_true(b is RogueRoombaBehavior, "ROGUE_ROOMBA kind must dispatch to RogueRoombaBehavior")


# ---------------------------------------------------------------------------
# DogKnightBehavior (issue #163) — raised defense, drunk charge, mead drop.
# ---------------------------------------------------------------------------

class _MockDogEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE

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


func test_dog_knight_charge_timer_fires():
	# Acceptance #2: after the ~5s cooldown elapses, wants_to_charge() is true
	# and begin_charge() (called by _drive_dog_knight in enemy.gd) starts it.
	var b := DogKnightBehavior.new()
	var e := _MockDogEnemy.new()
	for _i in range(5):
		b.tick(1.0, e)
	assert_true(b.wants_to_charge(), "wants_to_charge should be true after 5s cooldown")
	b.begin_charge(Vector2.RIGHT)
	assert_true(b.is_charging, "charge should begin when begin_charge is called")


func test_dog_knight_pick_charge_direction_varies_with_seed():
	# Acceptance #3: direction is randomized per charge. Two distinct seeds
	# should produce two distinct unit vectors. Seeds chosen empirically to
	# diverge — change in lockstep if the RNG algorithm changes.
	var b := DogKnightBehavior.new()
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 2
	var dir_a := b.pick_charge_direction(rng_a)
	var dir_b := b.pick_charge_direction(rng_b)
	assert_ne(dir_a, dir_b, "different seeds should produce different directions")
	assert_almost_eq(dir_a.length(), 1.0, 0.0001, "direction should be a unit vector")


func test_dog_knight_wobble_offset_varies_over_time():
	# Acceptance #4: lateral wobble is sinusoidal, not flat. Three sample
	# points across a charge should not all match.
	var w0 := DogKnightBehavior.wobble_offset(0.0)
	var w1 := DogKnightBehavior.wobble_offset(0.25)
	var w2 := DogKnightBehavior.wobble_offset(0.5)
	var all_equal := (
		is_equal_approx(w0, w1)
		and is_equal_approx(w1, w2)
	)
	assert_false(all_equal, "wobble offset should vary over time (sinusoidal)")


func test_dog_knight_burp_pending_after_charge_ends():
	# Acceptance #4 (BURP side): pending_burp flips true on the tick the
	# charge completes, so the Enemy-side observer spawns the FloatingText.
	var b := DogKnightBehavior.new()
	var e := _MockDogEnemy.new()
	b.begin_charge(Vector2.RIGHT)
	# CHARGE_DURATION = 1.0; one tick at 1.1s overshoots cleanly.
	b.tick(1.1, e)
	assert_false(b.is_charging, "charge should have ended after CHARGE_DURATION")
	assert_true(b.pending_burp, "pending_burp should be set on charge completion")


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


func test_dog_knight_idle_velocity_suppressed_while_charging():
	# Acceptance: while mid-charge (is_overriding_motion true), the idle pacer
	# path must not drive motion — the override takes exclusive control.
	var b := DogKnightBehavior.new()
	var e := _MockIdleEnemy.new()
	e.data = _MockIdleData.new()
	# Mid-charge: begin_charge flips is_charging true → is_overriding_motion true.
	b.begin_charge(Vector2.RIGHT)
	assert_true(b.is_overriding_motion(),
		"precondition: charge should make is_overriding_motion true")
	for _i in range(20):
		var v: Vector2 = b.idle_velocity(e, 0.05)
		assert_eq(v, Vector2.ZERO,
			"idle velocity must be zero while charge override is active")


func test_dog_knight_dead_enemy_skips_charge():
	var b := DogKnightBehavior.new()
	var e := _MockDogEnemy.new()
	e.state = 3  # DEAD
	for _i in range(6):
		b.tick(1.0, e)
	assert_false(b.wants_to_charge(), "dead dog knight should never want to charge")
	assert_false(b.is_charging, "dead dog knight should never be charging")


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


func test_catnip_dealer_holds_preferred_range():
	# Acceptance #1: at >PREFERRED_RANGE (+deadband), approach the player;
	# at <PREFERRED_RANGE (-deadband), back away to hold distance. The
	# behavior's desired_direction returns a unit vector the Enemy node
	# scales by move_speed. Issue text says "away (repositioning inward)"
	# at 150 — read as a typo for "toward" since the dealer's stated goal
	# is to *reach* ~120 from a too-far position. The test pins the
	# gameplay-sensible direction.
	var b := CatnipDealerBehavior.new()
	var far_dir := b.desired_direction(Vector2.ZERO, Vector2(150.0, 0.0))
	assert_eq(far_dir, Vector2(1.0, 0.0), "at 150px the dealer should approach the player")
	var near_dir := b.desired_direction(Vector2.ZERO, Vector2(90.0, 0.0))
	assert_eq(near_dir, Vector2(-1.0, 0.0), "at 90px the dealer should back away to hold range")


func test_catnip_dealer_flees_on_melee_entry():
	# Acceptance #2: ≤FLEE_RANGE (~40px) flips is_fleeing on; 50px is outside.
	var b := CatnipDealerBehavior.new()
	assert_true(b.is_fleeing(35.0), "35px should be inside flee range")
	assert_false(b.is_fleeing(50.0), "50px should be outside flee range")


func test_catnip_dealer_fire_timer_fires():
	# Acceptance #3: fire timer trips wants_to_fire() after ~2.5s. Driving 2.6s
	# of ticks without a player ref accrues the timer without queuing a fire.
	var b := CatnipDealerBehavior.new()
	var e := _MockDealerEnemy.new()
	for _i in range(26):
		b.tick(0.1, e)
	assert_true(b.wants_to_fire(), "wants_to_fire should be true after 2.6s")


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


func test_catnip_dealer_dead_enemy_skips_fire():
	# DEAD is the sink — a dead dealer must not accrue the fire timer or
	# queue a projectile. Same pattern as pigeon / roomba / dog knight.
	var b := CatnipDealerBehavior.new()
	var e := _MockDealerEnemy.new()
	e.state = 3  # EnemyAIState.State.DEAD
	for _i in range(30):
		b.tick(0.1, e)
	assert_false(b.wants_to_fire(),
		"dead dealer should never want to fire")
	assert_eq(b.pending_fire_target, null,
		"dead dealer should never queue a fire")


func test_catnip_dealer_fire_publishes_target_when_in_range():
	# Integration of fire-timer + range gate: with a player ref set inside
	# projectile range (>FLEE, <=MAX) the next ready tick should publish the
	# player position as pending_fire_target.
	var b := CatnipDealerBehavior.new()
	var e := _MockDealerEnemy.new()
	var p := _MockDealerPlayer.new()
	p.global_position = Vector2(150.0, 0.0)
	e._player_ref = p
	for _i in range(26):
		b.tick(0.1, e)
	assert_not_null(b.pending_fire_target,
		"fire should be queued once cooldown elapses and player is in range")
	assert_eq(b.pending_fire_target, Vector2(150.0, 0.0),
		"pending_fire_target should equal the player position at fire time")


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


func test_player_does_not_mask_walls_by_default():
	# Issue #263: players walk through walls (until #264 adds toggleable
	# phasing). The Player scene's CharacterBody2D must leave the walls bit
	# unmasked so move_and_slide ignores dungeon wall tiles.
	var scene: PackedScene = load("res://scenes/player.tscn")
	assert_not_null(scene, "player.tscn must load")
	var player := scene.instantiate() as CharacterBody2D
	add_child_autofree(player)
	assert_eq(player.collision_mask & EnemyBehavior.WALL_COLLISION_MASK, 0,
		"player CharacterBody2D must not mask the dedicated walls bit")


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


func test_dog_knight_idle_does_not_charge():
	# Same pattern as pigeon: IDLE dog accrues no cooldown, so wants_to_charge
	# never trips and _drive_dog_knight (the begin_charge caller) is gated.
	var b := DogKnightBehavior.new()
	var e := _MockDogEnemy.new()
	e.state = 0  # IDLE
	for _i in range(6):
		b.tick(1.0, e)
	assert_false(b.wants_to_charge(), "IDLE dog must not accrue charge cooldown")
	assert_false(b.is_charging, "IDLE dog must not begin a charge")


func test_dog_knight_chase_still_wants_charge():
	# Regression: cooldown still accrues in CHASE so the existing trigger fires.
	var b := DogKnightBehavior.new()
	var e := _MockDogEnemy.new()
	e.state = 1  # CHASE
	for _i in range(5):
		b.tick(1.0, e)
	assert_true(b.wants_to_charge(), "CHASE dog should still want to charge after cooldown")


func test_catnip_dealer_idle_does_not_fire():
	# Issue #261 — player in projectile range but enemy IDLE: no fire queued.
	var b := CatnipDealerBehavior.new()
	var e := _MockDealerEnemy.new()
	e.state = 0  # IDLE
	var p := _MockDealerPlayer.new()
	p.global_position = Vector2(120.0, 0.0)
	e._player_ref = p
	for _i in range(30):
		b.tick(0.1, e)
	assert_eq(b.pending_fire_target, null,
		"IDLE dealer must not queue a projectile even with player in range")
	assert_false(b.wants_to_fire(),
		"IDLE dealer must not accrue fire cadence")


func test_catnip_dealer_chase_still_fires():
	# Regression mirror of test_catnip_dealer_fire_publishes_target_when_in_range
	# now that the gate exists. Same setup, explicit CHASE.
	var b := CatnipDealerBehavior.new()
	var e := _MockDealerEnemy.new()
	e.state = 1  # CHASE
	var p := _MockDealerPlayer.new()
	p.global_position = Vector2(150.0, 0.0)
	e._player_ref = p
	for _i in range(26):
		b.tick(0.1, e)
	assert_not_null(b.pending_fire_target,
		"CHASE dealer should still publish a fire target after cooldown")


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
