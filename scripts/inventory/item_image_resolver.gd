class_name ItemImageResolver
extends RefCounted

# Single source of truth for resolving an ItemData to a texture path.
# Weapons first look up a per-id sprite (the new themed art per
# docs/weapon_art_checklist.md); if the file doesn't exist yet, fall back
# to the class-default sprite from WeaponDefinition.for_class().
# Armor/accessory items have no image in this version.

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

static func texture_path_for_item(item: ItemData) -> String:
	if item == null:
		return ""
	if item.slot != ItemData.Slot.WEAPON:
		return ""
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
