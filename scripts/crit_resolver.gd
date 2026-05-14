class_name CritResolver
extends RefCounted

# Pure crit-roll. Used by both physical (DamageResolver) and magic
# (SpellEffectResolver) paths once they wire in.
# roll_crit(0.0) is always false and roll_crit(1.0) is always true so
# callers can treat the result deterministically at the extremes.

static func roll_crit(crit_chance: float, rng: RandomNumberGenerator = null) -> bool:
	if crit_chance <= 0.0:
		return false
	if crit_chance >= 1.0:
		return true
	var roll := rng.randf() if rng != null else randf()
	return roll < crit_chance
