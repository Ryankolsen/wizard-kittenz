class_name EnemyAIState
extends RefCounted

# Pure-logic state machine for the basic chase-and-bite enemy. Same shape as
# DamageResolver / PartyScaler — a stateless RefCounted with static helpers
# operating against duck-typed inputs. The Node-side enemy.gd ticks this each
# physics frame to decide what behavior to run; tests exercise next_state
# directly without spinning up a SceneTree.

enum State { IDLE, CHASE, ATTACK, DEAD }

# Tunables. Per-kind variance (boss vs. standard) can override these by
# storing values on EnemyData later; today the constants are the source of
# truth so the state machine's behavior is reproducible from tests alone.
const DETECTION_RADIUS: float = 80.0
const MELEE_RANGE: float = 20.0
const ATTACK_COOLDOWN: float = 0.8
const CHASE_SPEED: float = 40.0

# Decides the next state given the current state, distance to the player, and
# current hp. The DEAD state is a sink — once dead, the enemy never resumes
# any other state, so a player wandering back into detection range can't
# reanimate a corpse. HP <= 0 always wins (a poison-tick that kills mid-
# attack still flips to DEAD this frame).
static func next_state(current: int, distance: float, hp: int) -> int:
	if hp <= 0:
		return State.DEAD
	if current == State.DEAD:
		return State.DEAD
	if distance <= MELEE_RANGE:
		return State.ATTACK
	if distance <= DETECTION_RADIUS:
		return State.CHASE
	return State.IDLE

static func state_name(s: int) -> String:
	match s:
		State.IDLE: return "Idle"
		State.CHASE: return "Chase"
		State.ATTACK: return "Attack"
		State.DEAD: return "Dead"
	return "Unknown"
