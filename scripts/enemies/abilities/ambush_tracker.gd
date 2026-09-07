class_name AmbushTracker
extends RefCounted

# Pure blind-arc + scare-charge accounting for the ambush archetype (PRD #518
# / issue #536). The counter to this archetype is attention, not movement:
# charge accrues only while the enemy sits inside the player's blind arc, and
# drains — not merely pauses — the instant the player faces it, so the scare
# genuinely cannot land on a player who is looking at the pickle. Landing a
# scare starts a long cooldown so the player can't be chain-locked (PRD user
# story 15).
#
# No SceneTree deps: every call takes plain Vector2 positions/facing so this
# is testable without a Node2D, the same separation EnemyAbility keeps between
# its pure cooldown/wind-up math and the scene-side Enemy node.

const MAX_CHARGE := 1.0
# Full charge in ~1.5s while unseen (near the PRD's petrify-duration range),
# draining twice as fast once faced so a glance is enough to reset it.
const CHARGE_RATE := 1.0 / 1.5
const DRAIN_RATE := 1.0 / 0.5
# Long cooldown after a landed scare (PRD user story 15 / issue #536 AC).
const SCARE_COOLDOWN := 10.0

var charge: float = 0.0
var _cooldown_remaining: float = 0.0


# True when `enemy_pos` sits in the half-plane behind the player's facing —
# the "blind side" the ambush archetype exploits. The boundary (exactly
# perpendicular) is treated as seen, not blind, so a player who is even
# marginally turned toward the enemy is credited with "keeping it in their
# sights" per the PRD's stated counter.
static func is_in_blind_arc(player_pos, player_facing, enemy_pos) -> bool:
	if player_pos == null or enemy_pos == null:
		return false
	if not (player_facing is Vector2):
		return false
	var facing: Vector2 = player_facing
	if facing == Vector2.ZERO:
		return false
	var to_enemy: Vector2 = (enemy_pos as Vector2) - (player_pos as Vector2)
	if to_enemy == Vector2.ZERO:
		return false
	return facing.normalized().dot(to_enemy.normalized()) < 0.0


func tick(delta: float, player_pos, player_facing, enemy_pos) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if delta <= 0.0:
		return
	if is_in_blind_arc(player_pos, player_facing, enemy_pos):
		charge = clampf(charge + CHARGE_RATE * delta, 0.0, MAX_CHARGE)
	else:
		charge = clampf(charge - DRAIN_RATE * delta, 0.0, MAX_CHARGE)


# True only at full charge, unseen, and off cooldown — every gate the PRD
# names for a scare landing.
func can_scare(player_pos, player_facing, enemy_pos) -> bool:
	if _cooldown_remaining > 0.0:
		return false
	if charge < MAX_CHARGE:
		return false
	return is_in_blind_arc(player_pos, player_facing, enemy_pos)


# Consumes the charge and starts the chain-lock-prevention cooldown. Called
# once a scare actually lands (AmbushAbility._on_commit).
func trigger_scare() -> void:
	charge = 0.0
	_cooldown_remaining = SCARE_COOLDOWN
