class_name HoomanAIState
extends RefCounted

# Pure-logic state machine for the rented human companion (PRD #491). Same
# shape as EnemyAIState — a stateless RefCounted with a static next_state
# helper operating against duck-typed inputs, ticked by the hooman Node each
# physics frame. No IDLE/DEAD: the hooman is a persistent companion while
# active (not aggro-gated) and is despawned rather than "dying" through this
# state machine.

enum State { FOLLOW, CHASE, ATTACK, HEAL }

# Tunables — separate constants from EnemyAIState's even though the shape
# mirrors it, since the hooman is tuned independently of enemy aggro ranges.
const DETECTION_RADIUS: float = 80.0
const MELEE_RANGE: float = 20.0
const ATTACK_COOLDOWN: float = 0.8
const HEAL_HP_THRESHOLD: float = 0.3
const HEAL_COOLDOWN: float = 10.0
# Flat burst amount per heal (issue #500) — a single cooldown-gated "pause to
# heal" per the PRD, not a per-second drip like HealingBox. Tuned to a
# meaningful chunk relative to HEAL_HP_THRESHOLD (roughly a third of a
# 20-30 max_hp player's missing HP at the trigger point) without being an
# outright full heal.
const HEAL_BURST_AMOUNT: int = 8

# Decides the next state given the current state, distance to the nearest
# eligible mob, the player's HP percent (0.0-1.0), whether the rental is
# active for the current floor, and the detection radius to use. An inactive
# rental always forces FOLLOW, overriding any mob/HP input. Otherwise HEAL
# preempts CHASE/ATTACK whenever HP drops below the threshold; failing that,
# distance decides CHASE vs. ATTACK vs. FOLLOW exactly like EnemyAIState.
static func next_state(current: int, distance_to_mob: float, player_hp_percent: float, is_active: bool, detection_radius: float = DETECTION_RADIUS) -> int:
	if not is_active:
		return State.FOLLOW
	if player_hp_percent < HEAL_HP_THRESHOLD:
		return State.HEAL
	if distance_to_mob <= MELEE_RANGE:
		return State.ATTACK
	if distance_to_mob <= detection_radius:
		return State.CHASE
	return State.FOLLOW

static func state_name(s: int) -> String:
	match s:
		State.FOLLOW: return "Follow"
		State.CHASE: return "Chase"
		State.ATTACK: return "Attack"
		State.HEAL: return "Heal"
	return "Unknown"
