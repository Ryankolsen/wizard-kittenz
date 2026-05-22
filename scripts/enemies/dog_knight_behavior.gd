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
