class_name RogueRoombaBehavior
extends EnemyBehavior

# Rogue Roomba behavior (issue #162, retuned in #262). Originally wall-bounced
# (reflected velocity off collision normals), replaced with per-frame homing
# toward the player: the Enemy node's base `_chase` already steers via
# `move_speed`, so the override flag is off and we just expose a pure
# `desired_direction` helper for tests / future motion consumers.
#
# The periodic FloorHazard damage trail and one-shot berserk (issue #584)
# moved onto the shared zone-denial and enrage archetypes (see
# AbilityLoadout.rogue_roomba_loadout, which documents the retired TRAIL_* /
# BERSERK_* constants that used to live here) -- this class no longer owns
# any of that state or tuning.

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

# Pure helper: unit-length direction from the roomba to the player. Re-evaluated
# every physics frame by the base _chase path (no override), which is what
# makes the chase "homing" instead of a one-time aim. Returns Vector2.ZERO when
# already on the player so the caller can leave velocity untouched.
func desired_direction(self_pos: Vector2, player_pos: Vector2) -> Vector2:
	var to_player := player_pos - self_pos
	if to_player == Vector2.ZERO:
		return Vector2.ZERO
	return to_player.normalized()
