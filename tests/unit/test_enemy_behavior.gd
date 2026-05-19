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

func test_rogue_roomba_reflect_velocity_off_left_normal():
	# Issue #162 acceptance #1: bouncing velocity (1, 0) off a wall whose
	# inward normal is (-1, 0) should reverse the X component → (-1, 0).
	# Pure static helper so the bounce math is verifiable without physics.
	var reflected := RogueRoombaBehavior.reflect_velocity(Vector2(1, 0), Vector2(-1, 0))
	assert_eq(reflected, Vector2(-1, 0), "velocity should reflect across the wall normal")


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
	# Acceptance #2: charge auto-triggers after the ~5s cooldown elapses.
	# Driving five 1.0s ticks against a mock accrues the cooldown; the
	# behavior auto-begins the charge on the threshold-crossing tick.
	var b := DogKnightBehavior.new()
	var e := _MockDogEnemy.new()
	for _i in range(5):
		b.tick(1.0, e)
	assert_true(b.is_charging, "charge should auto-begin after 5s cooldown")


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


func test_catnip_dealer_make_debuff_effect_maps_to_subclasses():
	# Confusion / slowness construct their respective PowerUpEffect; misfire
	# returns null since there's no time-bounded state to push onto the
	# PowerUpManager (the side effect, if any, fires at apply-time only).
	assert_true(CatnipDealerBehavior.make_debuff_effect(
		CatnipDealerBehavior.DEBUFF_CONFUSION) is ConfusionEffect)
	assert_true(CatnipDealerBehavior.make_debuff_effect(
		CatnipDealerBehavior.DEBUFF_SLOWNESS) is SlownessEffect)
	assert_null(CatnipDealerBehavior.make_debuff_effect(
		CatnipDealerBehavior.DEBUFF_MISFIRE),
		"misfire should not construct a PowerUpEffect")


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
