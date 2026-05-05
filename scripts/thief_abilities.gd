class_name ThiefAbilities
extends RefCounted

# Thief-specific combat helpers that don't fit the generic DamageResolver.
# Backstab is the headliner: an attacker.facing-aware swing that doubles
# damage when the target is facing away from the attacker. Modeled as a
# stateless static so the test can call it directly on dummy data without
# instantiating a scene.

const BACKSTAB_MULTIPLIER: float = 2.0
# Two unit vectors are "roughly aligned" when their dot product clears this
# threshold. 0.5 matches a 60-degree cone behind the target — generous enough
# that diagonal attacks read as "behind" instead of forcing pixel-perfect
# alignment, tight enough that side-stabs aren't free crits.
const BEHIND_ALIGNMENT_THRESHOLD: float = 0.5

# Returns damage actually dealt to the target. Duck-typed: attacker needs
# `attack: int` and `facing: Vector2`; target needs `defense: int`,
# `take_damage(int) -> int`, and `facing: Vector2`. CharacterData and
# EnemyData both satisfy this contract.
#
# Front-attack: max(1, attacker.attack - target.defense).
# Behind-attack: front-attack damage * BACKSTAB_MULTIPLIER, rounded down.
# A no-attack (attack <= 0) attacker still deals zero — preserves the
# DamageResolver invariant that a 0-attack swing is harmless even on a
# turned-away target.
static func backstab(attacker, target) -> int:
	var raw := int(attacker.attack)
	if raw <= 0:
		return 0
	var defense := int(target.defense)
	var base := maxi(1, raw - defense)
	var damage := base
	if is_behind(attacker, target):
		damage = int(float(base) * BACKSTAB_MULTIPLIER)
	return target.take_damage(damage)

# Attacker is "behind" target when their facing vectors point in roughly the
# same direction — i.e., the attacker is approaching from the target's back
# and the target is moving away. Same-direction facing is the cheapest proxy
# for "behind" that doesn't require world positions; positions land when
# combat moves past the swing-radius hitbox model.
static func is_behind(attacker, target) -> bool:
	var a: Vector2 = attacker.facing
	var t: Vector2 = target.facing
	if a == Vector2.ZERO or t == Vector2.ZERO:
		return false
	return a.normalized().dot(t.normalized()) >= BEHIND_ALIGNMENT_THRESHOLD
