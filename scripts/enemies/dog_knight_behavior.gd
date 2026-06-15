class_name DogKnightBehavior
extends EnemyBehavior

# Dog Knight (issue #163). Raised base defense (EnemyData.base_defense_for is
# the source of truth for the stat side), a ~5s drunk charge in a random
# direction with a sinusoidal lateral wobble, a "BURP" FloatingText on charge
# end, and a mead bottle pickup spawned at the death position that grants
# AleEffect when the player walks over it. Pure-data RefCounted — the Enemy
# node side observes pending_burp / pending_mead_drop_position / is_charging
# for SceneTree side effects, same separation as #161 / #162.

const CHARGE_COOLDOWN: float = 5.0
const CHARGE_DURATION: float = 1.0
const CHARGE_SPEED: float = 140.0
const WOBBLE_AMPLITUDE: float = 24.0
const WOBBLE_FREQUENCY: float = 8.0
const MEAD_POWER_UP_TYPE: String = PowerUpEffect.TYPE_ALE

# Idle wander tuning (PRD #391 / slice #393). Pacer at ~50% of chase speed,
# patrolling on a leash around the spawn. 1 == WanderProfile.Style.PACER; held
# as an int literal so the const block resolves at parse time without depending
# on WanderProfile's load order (Godot can't fold cross-class enum lookups into
# a `const`). Mirrors the haunted spray bottle's pattern in #392.
const IDLE_STYLE: int = 1
const IDLE_SPEED_FRACTION: float = 0.50
const IDLE_RADIUS: float = 64.0
const IDLE_CHANGE_CADENCE: float = 1.0
const IDLE_PAUSE_LENGTH: float = 0.6

var is_charging: bool = false
var charge_direction: Vector2 = Vector2.ZERO
var pending_burp: bool = false
# Variant null sentinel — Vector2 once the enemy has died and the Enemy-side
# observer has not yet consumed the spawn request. The observer clears it
# back to null after parenting the mead PowerUpPickup.
var pending_mead_drop_position = null

var _cooldown_elapsed: float = 0.0
var _charge_elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Lazily seeded from enemy_id so wander is reproducible per spawn. Same shape
# as HauntedSprayBottleBehavior._wander_profile.
var _wander_profile = null  # WanderProfile; untyped to keep load order resilient

func _init() -> void:
	_rng.randomize()

func wants_to_charge() -> bool:
	return not is_charging and _cooldown_elapsed >= CHARGE_COOLDOWN

# Picks a unit-vector direction from the supplied RNG. Exposed so tests can
# pin the random choice with a seeded RNG; runtime path uses the internal
# _rng seeded on _init.
func pick_charge_direction(rng: RandomNumberGenerator) -> Vector2:
	var angle := rng.randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle))

# Lateral wobble offset along the charge axis. Pure sine of time so the path
# reads as drunken; amplitude tuned so the lateral excursion is visible but
# the charge still tracks roughly its chosen direction.
static func wobble_offset(t: float) -> float:
	return sin(t * WOBBLE_FREQUENCY) * WOBBLE_AMPLITUDE

func begin_charge(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	charge_direction = direction.normalized()
	is_charging = true
	_charge_elapsed = 0.0
	_cooldown_elapsed = 0.0

func is_overriding_motion() -> bool:
	return is_charging


func idle_style() -> int:
	return IDLE_STYLE


func idle_speed_fraction() -> float:
	return IDLE_SPEED_FRACTION


# Idle-velocity hook. Returns Vector2.ZERO unless the enemy is in IDLE state
# and not mid-charge (the override path owns motion exclusively). Anchor is
# data.spawn_position when set, falling back to current position so legacy
# fixtures with spawn_position unset don't pull the wanderer to the origin.
func idle_velocity(enemy, delta: float) -> Vector2:
	if enemy == null:
		return Vector2.ZERO
	if is_overriding_motion():
		return Vector2.ZERO
	if enemy.get("state") != EnemyAIState.State.IDLE:
		return Vector2.ZERO
	_ensure_wander_profile(enemy)
	var chase_speed: float = EnemyAIState.CHASE_SPEED
	var ms = enemy.get("move_speed")
	if ms != null:
		chase_speed = float(ms)
	var params := {
		"idle_speed": chase_speed * IDLE_SPEED_FRACTION,
		"radius": IDLE_RADIUS,
		"change_cadence": IDLE_CHANGE_CADENCE,
		"pause_length": IDLE_PAUSE_LENGTH,
	}
	var anchor := _resolve_anchor(enemy)
	var current_pos: Vector2 = Vector2.ZERO
	var gp = enemy.get("global_position")
	if gp != null:
		current_pos = gp
	return _wander_profile.desired_velocity(IDLE_STYLE, params, anchor, current_pos, delta)


func _ensure_wander_profile(enemy) -> void:
	if _wander_profile != null:
		return
	var seed_value: int = 0
	var d = enemy.get("data")
	if d != null:
		var eid = d.get("enemy_id")
		if eid != null and str(eid) != "":
			seed_value = hash(eid)
	_wander_profile = WanderProfile.new(seed_value)


func _resolve_anchor(enemy) -> Vector2:
	var d = enemy.get("data")
	if d != null:
		var sp = d.get("spawn_position")
		if sp != null and sp != Vector2.ZERO:
			return sp
	var gp = enemy.get("global_position")
	if gp != null:
		return gp
	return Vector2.ZERO

# Called by the Enemy node on its `died` signal so the behavior can publish
# the mead drop request. Pure data — the observer reads pending_mead_drop_position
# next frame and clears it after parenting the PowerUpPickup.
func on_enemy_died(enemy) -> void:
	if enemy == null:
		return
	pending_mead_drop_position = enemy.global_position

func tick(delta: float, enemy) -> void:
	if enemy != null and enemy.get("state") == 3:  # EnemyAIState.State.DEAD
		return
	if is_charging:
		_advance_charge(delta, enemy)
		return
	# Aggro gate (issue #261): cooldown only accrues while CHASE or ATTACK so
	# an IDLE dog can't quietly charge up off-screen and then trigger the
	# instant a player wanders into range.
	if not EnemyBehavior.is_aggroed(enemy):
		return
	_cooldown_elapsed += delta

func _advance_charge(delta: float, enemy) -> void:
	if enemy == null:
		return
	_charge_elapsed += delta
	# Lateral wobble — perpendicular to the charge direction so the path
	# visibly weaves while still tracking the chosen heading.
	var perp := Vector2(-charge_direction.y, charge_direction.x)
	var step := charge_direction * CHARGE_SPEED * delta
	var lateral_delta := perp * (
		wobble_offset(_charge_elapsed) - wobble_offset(_charge_elapsed - delta)
	)
	enemy.global_position = enemy.global_position + step + lateral_delta
	if _charge_elapsed >= CHARGE_DURATION:
		is_charging = false
		pending_burp = true
