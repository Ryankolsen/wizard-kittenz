class_name DamageResolver
extends RefCounted

# Applies damage from attacker_stats to target. Returns damage actually dealt.
# Duck-typed: attacker_stats needs `attack: int`; target needs `defense: int` and
# `take_damage(int) -> int`. Both Health and EnemyData/CharacterData satisfy this.
# Defense reduces incoming damage with a floor of 1 — no zero-damage hits when the
# attacker has any positive attack value, so defense can blunt but not negate.
#
# Wire Combat Stats (PRD #85): three duck-typed stat reads gate the result —
#   attacker.dexterity + attacker.luck → HitResolver miss (returns 0)
#   attacker.crit_chance → CritResolver doubles raw pre-mitigation
#   target.evasion → physical-only dodge (returns 0)
# Missing fields default to 0/0.0 so EnemyData (which has none) still resolves.
# Optional `rng` lets tests force deterministic rolls; production passes null
# and falls back to the global randf().
static func apply(attacker_stats, target, rng: RandomNumberGenerator = null) -> int:
	var raw := int(attacker_stats.attack)
	if raw <= 0:
		return 0
	if not HitResolver.roll_hit(attacker_stats, 0, rng):
		return 0
	var crit_chance := _read_float(attacker_stats, "crit_chance", 0.0)
	if CritResolver.roll_crit(crit_chance, rng):
		raw *= 2
	var defense := int(target.defense)
	var mitigated := maxi(1, raw - defense)
	var evasion := _read_float(target, "evasion", 0.0)
	if _roll_evade(evasion, rng):
		return 0
	return target.take_damage(mitigated)

static func _read_float(obj, key: String, default_val: float) -> float:
	if obj == null or typeof(obj) != TYPE_OBJECT:
		return default_val
	if key in obj:
		return float(obj.get(key))
	return default_val

static func _roll_evade(evasion: float, rng: RandomNumberGenerator) -> bool:
	if evasion <= 0.0:
		return false
	if evasion >= 1.0:
		return true
	var roll := rng.randf() if rng != null else randf()
	return roll < evasion
