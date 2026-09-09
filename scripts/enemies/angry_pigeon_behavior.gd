class_name AngryPigeonBehavior
extends EnemyBehavior

# Angry Pigeon (issue #161). The hand-rolled dive-bomb charge state machine
# and hazard drop are gone (issue #583) — the dive is now the composed
# TelegraphedChargeAbility and the hazard drop is the composed
# ZoneDenialAbility, both driven generically by the Enemy node's ability pump
# (see AbilityLoadout.angry_pigeon_loadout). This file is left owning only
# idle wander tuning.

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
