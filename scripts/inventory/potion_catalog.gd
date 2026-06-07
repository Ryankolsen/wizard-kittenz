class_name PotionCatalog
extends RefCounted

# Static registry of every potion in the game (PRD #358 / slice 1). Pure data —
# every later slice (effect resolver, belt, shop integration, save layer, UI)
# iterates this list rather than hardcoding the three starter potions, so a new
# potion only needs an entry here. Mirrors SkillTree's static-factory pattern.

static func all() -> Array:
	var out: Array = []
	# Magnitudes / durations are PRD-stated starting values; tuning happens in
	# the QA slice (#368). Categories double as the shop-tab id in slice 5.
	out.append(_seed(PotionDefinition.make(
		"health_potion", "Health Potion",
		"Restores 50% of your max HP.",
		PotionDefinition.EffectKind.HEAL_PERCENT, 50, 0.0, "healing")))
	out.append(_seed(PotionDefinition.make(
		"mana_potion", "Mana Potion",
		"Restores 50% of your max MP.",
		PotionDefinition.EffectKind.MANA_PERCENT, 50, 0.0, "mana")))
	out.append(_seed(PotionDefinition.make(
		"shield_potion", "Shield Potion",
		"Absorbs the next 30 damage.",
		PotionDefinition.EffectKind.SHIELD, 30, 30.0, "protect")))
	return out

# Attach the generic per-kind icon (slice 8). PotionImageResolver is the single
# source of art truth — reused across every potion of a kind, with per-id
# overrides reserved for future special potions — so the catalog stays the one
# place a new potion is registered and its icon comes along for free.
static func _seed(def: PotionDefinition) -> PotionDefinition:
	def.icon = PotionImageResolver.texture_for(def)
	return def

static func find(potion_id: String) -> PotionDefinition:
	for d in all():
		if d.id == potion_id:
			return d
	return null
