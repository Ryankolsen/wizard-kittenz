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

var pending_trail_spawn: bool = false
var is_berserk: bool = false
# Monotonic counter incremented exactly once when the berserk threshold is
# first crossed. Observer reads >0 once, applies the tint / speed buff /
# FloatingText, and never re-fires even if HP fluctuates back above 30%.
var berserk_entry_count: int = 0

var _trail_elapsed: float = 0.0

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
