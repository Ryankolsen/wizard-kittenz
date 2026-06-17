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

# Lazily seeded from enemy_id so wander is reproducible per spawn. Untyped to
# keep load order resilient.
var _wander_profile = null  # WanderProfile


func idle_style() -> int:
	return IDLE_STYLE


func idle_speed_fraction() -> float:
	return IDLE_SPEED_FRACTION


# Idle-velocity hook. Returns Vector2.ZERO unless the enemy is in IDLE state and
# not mid-dive (is_overriding_motion() owns motion exclusively during a charge).
# Anchor falls back to current position when data.spawn_position isn't set.
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
