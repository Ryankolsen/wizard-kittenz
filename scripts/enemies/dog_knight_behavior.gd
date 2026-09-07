class_name DogKnightBehavior
extends EnemyBehavior

# Dog Knight (issue #163). Raised base defense (EnemyData.base_defense_for is
# the source of truth for the stat side), a "BURP" FloatingText hookup and a
# mead bottle pickup spawned at the death position that grants AleEffect when
# the player walks over it. Pure-data RefCounted — the Enemy node side
# observes pending_mead_drop_position for SceneTree side effects, same
# separation as #161 / #162.
#
# The drunk charge itself (issue #581 / PRD #518) is now the composed
# TelegraphedChargeAbility from AbilityLoadout.dog_knight_loadout — this file
# no longer owns any charge state. Aiming still comes from the Enemy node's
# own `_player_ref` (the ability's `target_position` reads it), which is why
# the charge still tracks the local player after the migration.

const MEAD_POWER_UP_TYPE: String = PowerUpEffect.TYPE_ALE

# Idle wander tuning (PRD #391 / slice #393). Pacer at ~50% of chase speed,
# patrolling on a leash around the spawn. 1 == WanderProfile.Style.PACER; held
# as an int literal so the const block resolves at parse time without depending
# on WanderProfile's load order (Godot can't fold cross-class enum lookups into
# a `const`). Mirrors the haunted spray bottle's pattern in #392.
const IDLE_STYLE: int = 1
const IDLE_SPEED_FRACTION: float = 0.50
const IDLE_RADIUS: float = 64.0
const IDLE_CHANGE_CADENCE: float = 1.0
const IDLE_PAUSE_LENGTH: float = 0.6

var pending_burp: bool = false
# Variant null sentinel — Vector2 once the enemy has died and the Enemy-side
# observer has not yet consumed the spawn request. The observer clears it
# back to null after parenting the mead PowerUpPickup.
var pending_mead_drop_position = null


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

# Called by the Enemy node on its `died` signal so the behavior can publish
# the mead drop request. Pure data — the observer reads pending_mead_drop_position
# next frame and clears it after parenting the PowerUpPickup.
func on_enemy_died(enemy) -> void:
	if enemy == null:
		return
	pending_mead_drop_position = enemy.global_position
