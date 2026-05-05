class_name SpellEffectResolver
extends RefCounted

# Dispatches a Spell's effect over a target list based on EffectKind. Spells
# bypass DamageResolver — their `power` is the raw damage dealt, so defense
# does not mitigate magic. (Magic-vs-physical balance lever is a follow-up;
# for the tracer, distinct kinds give distinct combat behavior.)
# Returns total HP removed across all targets so callers can drive popups /
# kill-reward XP awards from a single number.

static func apply(spell: Spell, _caster: CharacterData, targets: Array) -> int:
	if spell == null:
		return 0
	var total := 0
	match spell.effect_kind:
		Spell.EffectKind.DAMAGE:
			for t in targets:
				if t != null and t.is_alive():
					total += t.take_damage(spell.power)
					break
		Spell.EffectKind.AREA:
			for t in targets:
				if t != null and t.is_alive():
					total += t.take_damage(spell.power)
		Spell.EffectKind.BUFF:
			# No-op for the tracer. Future: register an active buff on caster
			# (+power attack for `cooldown` seconds, refresh on re-cast). The
			# kind classification is enough to mark it as a distinct effect.
			pass
	return total
