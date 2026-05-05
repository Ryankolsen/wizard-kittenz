class_name DamageResolver
extends RefCounted

# Applies damage from attacker_stats to target. Returns damage actually dealt.
# Duck-typed: attacker_stats needs `attack: int`; target needs `defense: int` and
# `take_damage(int) -> int`. Both Health and EnemyData/CharacterData satisfy this.
# Defense reduces incoming damage with a floor of 1 — no zero-damage hits when the
# attacker has any positive attack value, so defense can blunt but not negate.
static func apply(attacker_stats, target) -> int:
	var raw := int(attacker_stats.attack)
	if raw <= 0:
		return 0
	var defense := int(target.defense)
	var mitigated := maxi(1, raw - defense)
	return target.take_damage(mitigated)
