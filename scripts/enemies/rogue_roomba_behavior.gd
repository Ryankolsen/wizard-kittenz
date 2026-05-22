class_name RogueRoombaBehavior
extends EnemyBehavior

# Rogue Roomba behavior (issue #162). Wall-bounce movement (reflects velocity
# off collision normals instead of re-steering), periodic FloorHazard damage
# trail segments dropped at the roomba's position, and a one-shot berserk
# entry at ≤30% HP that bumps speed and tints the sprite red. Pure-logic state
# lives on this RefCounted so trail timing, berserk threshold detection, and
# the reflection math are testable without a SceneTree — the Enemy node side
# observes `pending_trail_spawn` / `berserk_entry_count` to spawn the hazard
# and apply the tint / speed buff / FloatingText.

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

static func reflect_velocity(velocity: Vector2, normal: Vector2) -> Vector2:
	return velocity.bounce(normal)

func is_overriding_motion() -> bool:
	# Roomba uses its own velocity vector and wall-bounce reflection rather
	# than re-steering toward the player each frame — Enemy node delegates
	# the move_and_slide / slide-collision loop while we skip the chase path.
	return true

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
