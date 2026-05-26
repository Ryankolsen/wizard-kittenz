class_name ItemImageResolver
extends RefCounted

# Single source of truth for resolving an ItemData to a texture path.
# Weapons derive their image from the item's class via WeaponDefinition;
# armor/accessory items have no image in this version.

static func texture_path_for_item(item: ItemData) -> String:
	if item == null:
		return ""
	if item.slot != ItemData.Slot.WEAPON:
		return ""
	if item.allowed_classes.is_empty():
		return ""
	var def := WeaponDefinition.for_class(item.allowed_classes[0])
	if def == null:
		return ""
	return def.texture_path
