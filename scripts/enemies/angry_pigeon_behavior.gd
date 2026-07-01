class_name AngryPigeonBehavior
extends EnemyBehavior

# Angry Pigeon dive-bomb (issue #161). Periodic high-speed straight-line
# charge toward a locked target position; on impact, drops a FloorHazard
# slow zone. Pure-logic state lives on this RefCounted so the cooldown /
# charge / completion edges are testable without a SceneTree — the Enemy
# node side just observes `pending_hazard_position` to spawn the hazard
# and surfaces the VFX (motion trail, SPLAT FloatingText).

const CHARGE_COOLDOWN: float = 4.0
const CHARGE_SPEED: float = 120.0
const ARRIVAL_DIST: float = 4.0
const HAZARD_DURATION: float = 3.0
const HAZARD_SLOW_PERCENT: float = 0.5
const HAZARD_RADIUS: float = 32.0
const HAZARD_COLOR: Color = Color(0.6, 0.5, 0.7, 0.4)

# Idle wander tuning (PRD #391; retuned to pacer). Pacer at ~35% of chase speed,
# patrolling on a leash around the spawn. Shares the SAME pacer path tuning as
# the catnip dealer so the two read as the same patrol. 1 == WanderProfile.Style.PACER;
# int literal so the const block resolves at parse time (Godot can't fold
# cross-class enum lookups into a `const`).
const IDLE_STYLE: int = 1
const IDLE_SPEED_FRACTION: float = 0.35
const IDLE_RADIUS: float = 48.0
const IDLE_CHANGE_CADENCE: float = 1.0
const IDLE_PAUSE_LENGTH: float = 0.6

var is_charging: bool = false
var charge_target: Vector2 = Vector2.ZERO
var charge_completed: bool = false
# Variant null sentinel — Vector2 once a charge has completed and the
# Enemy-side observer has not yet consumed the spawn request. The
# observer clears it back to null after parenting the FloorHazard.
var pending_hazard_position = null

var _cooldown_elapsed: float = 0.0


func idle_style() -> int:
	return IDLE_STYLE


func idle_speed_fraction() -> float:
	return IDLE_SPEED_FRACTION


func idle_radius() -> float:
	return IDLE_RADIUS


func idle_change_cadence() -> float:
	return IDLE_CHANGE_CADENCE


func idle_pause_length() -> float:
	return IDLE_PAUSE_LENGTH


func wants_to_charge() -> bool:
	return not is_charging and _cooldown_elapsed >= CHARGE_COOLDOWN

func begin_charge(target_pos: Vector2) -> void:
	charge_target = target_pos
	is_charging = true
	charge_completed = false
	_cooldown_elapsed = 0.0

func is_overriding_motion() -> bool:
	# During the dive bomb the behavior writes global_position directly,
	# so the Enemy node must skip its chase/attack match block this frame.
	return is_charging

func tick(delta: float, enemy) -> void:
	# DEAD state is the sink — a dead pigeon neither accrues cooldown nor
	# moves toward a stale charge target. Matches the enemy.gd DEAD skip
	# (issue #157 wiring) so behavior never ticks logic after queue_free.
	if enemy != null and enemy.get("state") == 3:  # EnemyAIState.State.DEAD
		return
	if is_charging:
		_advance_charge(delta, enemy)
		return
	# Aggro gate (issue #261): only accrue cooldown / initiate a dive while
	# CHASE or ATTACK. A committed charge above is allowed to complete even
	# after the player leaves range.
	if not EnemyBehavior.is_aggroed(enemy):
		return
	_cooldown_elapsed += delta
	# Auto-trigger when a player is in sight. Reads enemy._player_ref directly
	# (the same cached chase target Enemy._find_player populates) so the
	# behavior locks onto the same target the chase state was tracking.
	if enemy != null and wants_to_charge():
		var player = enemy.get("_player_ref")
		if player != null and player is Node2D:
			begin_charge((player as Node2D).global_position)

func _advance_charge(delta: float, enemy) -> void:
	if enemy == null:
		return
	var current: Vector2 = enemy.global_position
	var to_target := charge_target - current
	var dist := to_target.length()
	var step := CHARGE_SPEED * delta
	if dist <= step or dist <= ARRIVAL_DIST:
		enemy.global_position = charge_target
		is_charging = false
		charge_completed = true
		pending_hazard_position = charge_target
	else:
		enemy.global_position = current + to_target.normalized() * step
