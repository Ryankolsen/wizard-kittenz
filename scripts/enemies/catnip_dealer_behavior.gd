class_name CatnipDealerBehavior
extends EnemyBehavior

# Catnip Dealer (issue #164). Maintains ~PREFERRED_RANGE from the player rather
# than chasing, flees on melee entry (≤FLEE_RANGE), fires a catnip-bag
# EnemyProjectile every FIRE_INTERVAL seconds while in firing distance, and on
# hit applies one of three randomly-chosen debuffs (confusion / slowness /
# misfire). Pure-data RefCounted.
#
# The kiting and fire cadence (issue #582 / PRD #518) are now the composed
# RetreatAndFireAbility from AbilityLoadout.catnip_dealer_loadout — constructed
# with this file's own tuning constants below and the telegraph flag on — so
# this class no longer owns desired_direction/is_overriding_motion/
# wants_to_fire/pending_fire_target. The constants stay here because they
# remain the tuning's source of truth (the loadout table reads them, and the
# Enemy node still reads the PROJECTILE_* ones for the catnip bag's visuals)
# and because the "tuning preserved" test compares the migrated ability
# against them directly. What's left on this class is what the archetype
# doesn't own: idle wander and the debuff-on-hit selection, which the Enemy
# node still reaches via pick_debuff() once the ability's pending_fire_target
# fires.

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

# Idle wander tuning (PRD #391; retuned to pacer). Pacer at ~35% of chase speed,
# patrolling on a leash around the spawn. Shares the SAME pacer path tuning as
# the angry pigeon so the two read as the same patrol. 1 == WanderProfile.Style.PACER;
# held as an int literal so the const block resolves at parse time without
# depending on WanderProfile's load order (Godot can't fold cross-class enum
# lookups into a `const`).
const IDLE_STYLE: int = 1
const IDLE_SPEED_FRACTION: float = 0.35
const IDLE_RADIUS: float = 48.0
const IDLE_CHANGE_CADENCE: float = 1.0
const IDLE_PAUSE_LENGTH: float = 0.6

# Variant null sentinel — Vector2 once the projectile reports a hit and the
# observer should spawn the green-burst VFX at the impact point.
var pending_burst_position = null


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

# Picks one of the three debuff type ids uniformly. Defaults to the
# behaviour's own RNG, seeded from the enemy's stable spawn id (issue #534)
# so the bag applies the same debuff on every co-op client. Exposed with an
# explicit-RNG override so tests can pin the choice.
func pick_debuff(rng: RandomNumberGenerator = null) -> String:
	var r := rng if rng != null else _ensure_rng(null)
	var idx := r.randi_range(0, DEBUFF_TYPES.size() - 1)
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

# Kiting and fire cadence are the composed RetreatAndFireAbility's job now
# (issue #582); this override exists solely to seed the debuff RNG from the
# enemy's stable spawn id (issue #534) before pick_debuff is ever called, so
# the roll is deterministic on every co-op client regardless of when the
# dealer aggroes. The Enemy node still calls this every physics frame
# (the ability pump is a separate, parallel tick over `abilities`).
func tick(_delta: float, enemy) -> void:
	_ensure_rng(enemy)
