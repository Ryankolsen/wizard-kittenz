class_name HauntedSprayBottleBehavior
extends EnemyBehavior

# Haunted Spray Bottle (issue #165; migrated onto the shared cone-spray
# archetype by issue #585 — the last of the five standard mobs). Holds
# ~PREFERRED_RANGE from the player and fires a 3-projectile cone (center +
# ±CONE_ANGLE_DEG) every FIRE_INTERVAL seconds, applies WetEffect on hit, and
# floats over terrain (Enemy node sets collision_mask = 0 when
# ignores_wall_collision is true).
#
# The fire cadence itself (the retired _fire_elapsed/wants_to_fire/tick and
# the pending_fire_aim/pending_cone_origin handoff) is gone — it now lives on
# the composed ConeSprayAbility (AbilityLoadout.haunted_spray_bottle_loadout),
# whose wind-up draws the cone in the uniform amber-to-red telegraph before
# the spray commits, rather than flashing it at the shot the way the retired
# cadence did. compute_cone_directions and make_wet_description stay here —
# Enemy._observe_haunted_spray_bottle still calls both, on the ability's
# WINDUP -> COMMIT edge, to fire the same 3 projectiles as before. Pure-data
# RefCounted; the Enemy-side observer spawns projectiles + the debuff-name
# FloatingText, same separation as the prior four kinds.

const PREFERRED_RANGE: float = 100.0
const RANGE_DEADBAND: float = 8.0
const FIRE_INTERVAL: float = 2.0
const CONE_ANGLE_DEG: float = 15.0
const PROJECTILE_SPEED: float = 180.0
const PROJECTILE_RADIUS: float = 6.0
const PROJECTILE_COLOR: Color = Color(0.4, 0.75, 1.0, 1.0)
const PROJECTILE_MAX_RANGE: float = 320.0
const WET_DURATION: float = 3.0

# Idle wander tuning (PRD #391 / slice #392). Stationary-ish: tiny shuffle
# at ~10% of chase speed within a small tether around the spawn point.
# 0 == WanderProfile.Style.STATIONARY_ISH; held as an int literal so the const
# block is resolvable at parse time without depending on WanderProfile's load
# order (Godot can't fold cross-class enum lookups into a `const`).
const IDLE_STYLE: int = 0
const IDLE_SPEED_FRACTION: float = 0.10
const IDLE_RADIUS: float = 24.0
const IDLE_CHANGE_CADENCE: float = 0.6
const IDLE_PAUSE_LENGTH: float = 1.5

# True so the Enemy node clears its collision_mask on _ready — the spray
# bottle floats through dungeon walls (acceptance #6). Read once at spawn
# time, no per-frame check needed.
var ignores_wall_collision: bool = true

func is_overriding_motion() -> bool:
	return false

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

# Pure helper returning a unit-length direction vector (or Vector2.ZERO inside
# the deadband). Inside PREFERRED_RANGE → away; outside → toward. No flee
# zone: the spray bottle's range is its melee distance.
func desired_direction(self_pos: Vector2, player_pos: Vector2) -> Vector2:
	var to_player := player_pos - self_pos
	var dist := to_player.length()
	if dist == 0.0:
		return Vector2.RIGHT
	if dist < PREFERRED_RANGE - RANGE_DEADBAND:
		return -to_player.normalized()
	if dist > PREFERRED_RANGE + RANGE_DEADBAND:
		return to_player.normalized()
	return Vector2.ZERO

# Returns the 3 unit-vector aim directions for the cone: center + ±CONE_ANGLE.
# Pure static so tests can verify spread without instantiating the behavior.
static func compute_cone_directions(aim_dir: Vector2) -> Array:
	var base := aim_dir
	if base == Vector2.ZERO:
		base = Vector2.RIGHT
	else:
		base = base.normalized()
	var spread := deg_to_rad(CONE_ANGLE_DEG)
	return [base, base.rotated(spread), base.rotated(-spread)]

# Description of the on-hit debuff — a (type_id, duration) pair routed through
# Player.apply_debuff → PowerUpManager.apply. The behavior never constructs the
# concrete effect class itself, so adding/renaming an effect kind doesn't
# require touching enemy scripts. Same shape as CatnipDealerBehavior.
static func make_wet_description() -> Dictionary:
	return {"type_id": PowerUpEffect.TYPE_WET, "duration": WET_DURATION}
