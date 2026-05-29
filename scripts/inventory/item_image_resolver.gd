class_name ItemImageResolver
extends RefCounted

# Single source of truth for resolving an ItemData to a texture path.
# Weapons first look up a per-id sprite (the new themed art per
# docs/weapon_art_checklist.md); if the file doesn't exist yet, fall back
# to the class-default sprite from WeaponDefinition.for_class().
# Armor/accessory items resolve via a per-id override (empty for now),
# then a slot+rarity tier image gated on ResourceLoader.exists.

const _PER_ID_SPRITES := {
	# Battle Kitten — slice 1
	"iron_sword": "res://assets/sprites/weapon_slippery_mackerel.png",
	"rusted_dagger": "res://assets/sprites/weapon_pointy_stick.png",
	"shop_iron_dirk": "res://assets/sprites/weapon_butter_knife.png",
	"silver_sword": "res://assets/sprites/weapon_alley_cat_cutlass.png",
	"knights_sabre": "res://assets/sprites/weapon_tin_knight_sabre.png",
	"enchanted_blade": "res://assets/sprites/weapon_clawbur.png",
	"dragonslayer_greatsword": "res://assets/sprites/weapon_catana.png",
	# Wizard Kitten — slice 2
	"apprentice_wand": "res://assets/sprites/weapon_birthday_sparkler.png",
	"novice_wand": "res://assets/sprites/weapon_firefly_jar.png",
	"arcane_staff": "res://assets/sprites/weapon_crackle_wand.png",
	"runed_staff": "res://assets/sprites/weapon_stormtwig_staff.png",
	"starfire_rod": "res://assets/sprites/weapon_comet_caller.png",
	"voidcaller_staff": "res://assets/sprites/weapon_wand_of_the_big_bang.png",
	"shop_archmage_staff": "res://assets/sprites/weapon_archmage_astrolabe.png",
}

# Per-id override for armor/accessory bespoke art. Empty for now; entries
# here win over the slot+rarity tier image when the override file exists.
const _GEAR_PER_ID_OVERRIDES := {}

const _TIER_SPRITES := {
	ItemData.Slot.ARMOR: {
		ItemData.Rarity.COMMON: "res://assets/sprites/armor_common.png",
		ItemData.Rarity.RARE: "res://assets/sprites/armor_rare.png",
		ItemData.Rarity.EPIC: "res://assets/sprites/armor_epic.png",
	},
	ItemData.Slot.ACCESSORY: {
		ItemData.Rarity.COMMON: "res://assets/sprites/accessory_common.png",
		ItemData.Rarity.RARE: "res://assets/sprites/accessory_rare.png",
		ItemData.Rarity.EPIC: "res://assets/sprites/accessory_epic.png",
	},
}

static func texture_path_for_item(item: ItemData) -> String:
	if item == null:
		return ""
	if item.slot == ItemData.Slot.WEAPON:
		if _PER_ID_SPRITES.has(item.id):
			var path: String = _PER_ID_SPRITES[item.id]
			if ResourceLoader.exists(path):
				return path
		if item.allowed_classes.is_empty():
			return ""
		var def := WeaponDefinition.for_class(item.allowed_classes[0])
		if def == null:
			return ""
		return def.texture_path
	if _GEAR_PER_ID_OVERRIDES.has(item.id):
		var override_path: String = _GEAR_PER_ID_OVERRIDES[item.id]
		if ResourceLoader.exists(override_path):
			return override_path
	var slot_tiers: Dictionary = _TIER_SPRITES.get(item.slot, {})
	var tier_path: String = slot_tiers.get(item.rarity, "")
	if tier_path != "" and ResourceLoader.exists(tier_path):
		return tier_path
	return ""
