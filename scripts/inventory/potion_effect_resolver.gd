class_name PotionEffectResolver
extends RefCounted

# PRD #358 / slice 3. Pure entry point that dispatches a PotionDefinition's
# effect onto a target CharacterData. Mirrors SpellEffectResolver.apply:
# static, no node access, returns the amount applied so callers (HUD popups,
# slice 8 belt feedback) can render a single number without re-reading state.
#
# Decision: the three EffectKinds share no code with SpellEffectResolver —
# HEAL_PERCENT uses max-HP-scaled magnitude (potions are tuned to character
# growth, spells are tuned to spell power + magic_attack), MANA_PERCENT has
# no spell analogue, and SHIELD wraps CharacterData.add_shield which already
# encapsulates the absorb-pool semantics (slice 2). Keeping the two
# resolvers independent means a potion magnitude change can never silently
# rebalance spells.

static func apply(definition: PotionDefinition, target) -> int:
	if definition == null or target == null:
		return 0
	match definition.effect_kind:
		PotionDefinition.EffectKind.HEAL_PERCENT:
			if not target.has_method("heal"):
				return 0
			var max_hp := int(_read(target, "max_hp", 0))
			var amount := int(floor(float(max_hp) * float(definition.magnitude) / 100.0))
			return int(target.heal(amount))
		PotionDefinition.EffectKind.MANA_PERCENT:
			# CharacterData has no restore_mana() helper, so the resolver
			# mutates magic_points directly with the same clamp-at-max
			# semantics CharacterData.heal uses for HP. Returning the
			# actual delta lets callers render "+N MP" floating text with
			# the post-clamp value.
			if not ("magic_points" in target and "max_mp" in target):
				return 0
			var max_mp := int(target.get("max_mp"))
			var current := int(target.get("magic_points"))
			var amount_mp := int(floor(float(max_mp) * float(definition.magnitude) / 100.0))
			var restored := mini(amount_mp, max_mp - current)
			if restored <= 0:
				return 0
			target.set("magic_points", current + restored)
			return restored
		PotionDefinition.EffectKind.SHIELD:
			if not target.has_method("add_shield"):
				return 0
			target.add_shield(definition.magnitude, definition.duration)
			return definition.magnitude
	return 0

static func _read(obj, key: String, default_val):
	if obj == null:
		return default_val
	if key in obj:
		return obj.get(key)
	return default_val
