class_name CatnipDealerBehavior
extends EnemyBehavior

# Catnip Dealer (issue #164). Maintains ~PREFERRED_RANGE from the player rather
# than chasing, flees on melee entry (≤FLEE_RANGE), fires a catnip-bag
# EnemyProjectile every FIRE_INTERVAL seconds while in firing distance, and on
# hit applies one of three randomly-chosen debuffs (confusion / slowness /
# misfire). Pure-data RefCounted — the Enemy node side observes
# `pending_fire_target` to spawn the projectile and surfaces the green-burst
# VFX + debuff-name FloatingText from the projectile's on_hit callback.

const PREFERRED_RANGE: float = 120.0
const FLEE_RANGE: float = 40.0
const RANGE_DEADBAND: float = 8.0
const FIRE_INTERVAL: float = 2.5
const PROJECTILE_SPEED: float = 160.0
const PROJECTILE_RADIUS: float = 8.0
const PROJECTILE_COLOR: Color = Color(0.5, 0.85, 0.3, 1.0)
const PROJECTILE_MAX_RANGE: float = 360.0
const DEBUFF_DURATION: float = 3.0
const BURST_COLOR: Color = Color(0.5, 0.85, 0.3, 0.6)
const BURST_RADIUS: float = 24.0
const BURST_DURATION: float = 0.35

const DEBUFF_CONFUSION: String = "confusion"
const DEBUFF_SLOWNESS: String = "slowness"
const DEBUFF_MISFIRE: String = "misfire"
const DEBUFF_TYPES: Array = [DEBUFF_CONFUSION, DEBUFF_SLOWNESS, DEBUFF_MISFIRE]

# Variant null sentinel — Vector2 once a fire is queued and the Enemy-side
# observer has not yet consumed the spawn request. Observer clears it after
# parenting the EnemyProjectile.
var pending_fire_target = null
# Variant null sentinel — Vector2 once the projectile reports a hit and the
# observer should spawn the green-burst VFX at the impact point.
var pending_burst_position = null

var _fire_elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func is_overriding_motion() -> bool:
	return false

# True when the player is inside the melee threshold and the dealer should
# back away rather than hold range. Exposed for tests so the threshold is
# verified without driving a full physics tick.
func is_fleeing(player_distance: float) -> bool:
	return player_distance <= FLEE_RANGE

# Pure helper returning a unit-length direction vector (or Vector2.ZERO inside
# the deadband). Positive magnitude only — the Enemy node scales by move_speed.
# Flee zone (≤FLEE_RANGE): away from player.
# Inside preferred range (>FLEE_RANGE, <PREFERRED_RANGE-deadband): away.
# Outside preferred range (>PREFERRED_RANGE+deadband): toward player.
# Deadband around PREFERRED_RANGE: zero — hold position.
func desired_direction(self_pos: Vector2, player_pos: Vector2) -> Vector2:
	var to_player := player_pos - self_pos
	var dist := to_player.length()
	if dist == 0.0:
		return Vector2.RIGHT
	if dist <= FLEE_RANGE:
		return -to_player.normalized()
	if dist < PREFERRED_RANGE - RANGE_DEADBAND:
		return -to_player.normalized()
	if dist > PREFERRED_RANGE + RANGE_DEADBAND:
		return to_player.normalized()
	return Vector2.ZERO

func wants_to_fire() -> bool:
	return _fire_elapsed >= FIRE_INTERVAL

# Picks one of the three debuff type ids uniformly from the supplied RNG.
# Exposed so tests can pin the random choice with seeded RNGs; runtime path
# uses the internal _rng seeded on _init.
func pick_debuff(rng: RandomNumberGenerator) -> String:
	var idx := rng.randi_range(0, DEBUFF_TYPES.size() - 1)
	return DEBUFF_TYPES[idx]

# Description of the debuff to push at the player — a (type_id, duration) pair
# routed through Player.apply_debuff → PowerUpManager.apply. Empty Dictionary
# for misfire (no time-bounded state to track; apply_misfire handles its own
# side effect at hit time).
static func make_debuff_description(debuff_type: String) -> Dictionary:
	match debuff_type:
		DEBUFF_CONFUSION:
			return {"type_id": PowerUpEffect.TYPE_CONFUSION, "duration": DEBUFF_DURATION}
		DEBUFF_SLOWNESS:
			return {"type_id": PowerUpEffect.TYPE_SLOWNESS, "duration": DEBUFF_DURATION}
	return {}

# Misfire: no spell unlocked / equipped → no-op (acceptance #5). Duck-typed so
# a bare CharacterData with no spell tree (test mock or pre-spell save) passes
# through safely. Future iteration may put the equipped spell on cooldown
# rather than no-op.
static func apply_misfire(_player_data) -> void:
	return

static func floating_text_label(debuff_type: String) -> String:
	match debuff_type:
		DEBUFF_CONFUSION: return "CONFUSED"
		DEBUFF_SLOWNESS: return "SLOWED"
		DEBUFF_MISFIRE: return "MISFIRE"
	return ""

func tick(delta: float, enemy) -> void:
	if enemy != null and enemy.get("state") == 3:  # EnemyAIState.State.DEAD
		return
	# Aggro gate (issue #261): an IDLE dealer must not accrue fire cadence or
	# queue a projectile — fixes the "shot the moment the level loads" issue.
	if not EnemyBehavior.is_aggroed(enemy):
		return
	_fire_elapsed += delta
	if enemy == null:
		return
	var player = enemy.get("_player_ref")
	if player == null or not (player is Node2D):
		return
	if not wants_to_fire():
		return
	var player_node := player as Node2D
	var dist: float = enemy.global_position.distance_to(player_node.global_position)
	# Don't fire while in flee range — the dealer is busy retreating, and
	# point-blank projectile spawns are awkward. Also gate by projectile range
	# so a fire never leaves the dealer with a guaranteed miss.
	if dist <= FLEE_RANGE or dist > PROJECTILE_MAX_RANGE:
		return
	pending_fire_target = player_node.global_position
	_fire_elapsed = 0.0
