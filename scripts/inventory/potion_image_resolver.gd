class_name PotionImageResolver
extends RefCounted

# Single source of truth for resolving a PotionDefinition to its icon texture.
# Mirrors ItemImageResolver's tier-sprite pattern: base potions share GENERIC
# per-effect-kind art (one red/blue/green bottle reused across every potion of
# that kind), so a new potion reusing an existing kind needs zero new art.
# Future special / loot-box potions (e.g. the reserved gold tier) slot in via
# _PER_ID_SPRITES, which wins over the kind default when the file exists.

# Per-id bespoke art for special potions. Empty for now; gold-tier loot-box
# potions go here later and override the generic kind sprite.
const _PER_ID_SPRITES := {}

# Generic art keyed by effect kind — every potion of a kind reuses one bottle.
const _KIND_SPRITES := {
	PotionDefinition.EffectKind.HEAL_PERCENT: "res://assets/sprites/potion_red_sprite.png",
	PotionDefinition.EffectKind.MANA_PERCENT: "res://assets/sprites/potion_blue_sprite.png",
	PotionDefinition.EffectKind.SHIELD: "res://assets/sprites/potion_green_sprite.png",
}

static func texture_path_for(def: PotionDefinition) -> String:
	if def == null:
		return ""
	if _PER_ID_SPRITES.has(def.id):
		var override_path: String = _PER_ID_SPRITES[def.id]
		if ResourceLoader.exists(override_path):
			return override_path
	var kind_path: String = _KIND_SPRITES.get(def.effect_kind, "")
	if kind_path != "" and ResourceLoader.exists(kind_path):
		return kind_path
	return ""

static func texture_for(def: PotionDefinition) -> Texture2D:
	var path := texture_path_for(def)
	if path == "":
		return null
	return load(path)
