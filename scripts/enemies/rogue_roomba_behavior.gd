class_name RogueRoombaBehavior
extends EnemyBehavior

# Rogue Roomba behavior (issue #162, retuned in #262). Originally wall-bounced
# (reflected velocity off collision normals), replaced with per-frame homing
# toward the player: the Enemy node's base `_chase` already steers via
# `move_speed`, so the override flag is off and we just expose a pure
# `desired_direction` helper for tests / future motion consumers. Periodic
# FloorHazard damage trail and one-shot berserk (≤30% HP → speed ×1.5 + red
# tint) are preserved; berserk now scales the chase move_speed directly.

const TRAIL_INTERVAL: float = 0.3
const TRAIL_DURATION: float = 2.0
const TRAIL_DAMAGE_PER_SEC: float = 3.0
const TRAIL_RADIUS: float = 20.0
const TRAIL_COLOR: Color = Color(0.7, 0.4, 0.4, 0.4)
const BERSERK_HP_FRACTION: float = 0.3
const BERSERK_SPEED_MULTIPLIER: float = 1.5
const BERSERK_TINT: Color = Color(1.6, 0.5, 0.5, 1.0)

# Idle wander tuning (PRD #391 / slice #394). Restless at ~60% of chase speed —
# the most active mob. 2 == WanderProfile.Style.RESTLESS; held as an int literal
# so the const block resolves at parse time without depending on WanderProfile's
# load order (Godot can't fold cross-class enum lookups into a `const`). Same
# trick as the spray bottle (#392) and dog knight (#393).
const IDLE_STYLE: int = 2
const IDLE_SPEED_FRACTION: float = 0.60
const IDLE_RADIUS: float = 56.0
const IDLE_CHANGE_CADENCE: float = 0.25
const IDLE_PAUSE_LENGTH: float = 0.3

var pending_trail_spawn: bool = false
var is_berserk: bool = false
# Monotonic counter incremented exactly once when the berserk threshold is
# first crossed. Observer reads >0 once, applies the tint / speed buff /
# FloatingText, and never re-fires even if HP fluctuates back above 30%.
var berserk_entry_count: int = 0

var _trail_elapsed: float = 0.0

# Lazily seeded from enemy_id so wander is reproducible per spawn. Same shape
# as HauntedSprayBottleBehavior / DogKnightBehavior — untyped to keep load
# order resilient.
var _wander_profile = null  # WanderProfile


func idle_style() -> int:
	return IDLE_STYLE


func idle_speed_fraction() -> float:
	return IDLE_SPEED_FRACTION


# Idle-velocity hook. Returns Vector2.ZERO unless the enemy is in IDLE state.
# The roomba's chase/berserk path owns motion when aggroed; restless wander only
# drives an idle, unaggroed roomba scurrying around its spawn. Anchor falls
# back to current position when data.spawn_position isn't set so legacy fixtures
# don't snap to the origin.
func idle_velocity(enemy, delta: float) -> Vector2:
	if enemy == null:
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

# Pure helper: unit-length direction from the roomba to the player. Re-evaluated
# every physics frame by the base _chase path (no override), which is what
# makes the chase "homing" instead of a one-time aim. Returns Vector2.ZERO when
# already on the player so the caller can leave velocity untouched.
func desired_direction(self_pos: Vector2, player_pos: Vector2) -> Vector2:
	var to_player := player_pos - self_pos
	if to_player == Vector2.ZERO:
		return Vector2.ZERO
	return to_player.normalized()

func tick(delta: float, enemy) -> void:
	# DEAD is the sink — no trail accrual, no berserk check post-death.
	if enemy != null and enemy.get("state") == 3:  # EnemyAIState.State.DEAD
		return
	# Only drop trail while actively chasing — not while idle before detection.
	var s = enemy.get("state") if enemy != null else null
	if s == null or s == 0:  # EnemyAIState.State.IDLE
		return
	_trail_elapsed += delta
	if _trail_elapsed >= TRAIL_INTERVAL:
		_trail_elapsed = 0.0
		pending_trail_spawn = true
	_check_berserk(enemy)

func _check_berserk(enemy) -> void:
	if is_berserk or enemy == null:
		return
	var d = enemy.get("data")
	if d == null:
		return
	var max_hp_val = d.get("max_hp")
	var hp_val = d.get("hp")
	if max_hp_val == null or hp_val == null or int(max_hp_val) <= 0:
		return
	if float(hp_val) / float(max_hp_val) <= BERSERK_HP_FRACTION:
		is_berserk = true
		berserk_entry_count += 1
