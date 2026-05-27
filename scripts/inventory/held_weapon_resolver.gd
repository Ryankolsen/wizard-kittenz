class_name HeldWeaponResolver
extends RefCounted

# Shared resolver for "what weapon is the kitten holding right now" (PRD #280
# / issue #281). Single source of truth consumed by both CharacterAvatar
# (Items tab) and Player (combat) so the avatar and the combat sprite never
# disagree by construction.
#
# Input: an equipped ItemData (or null) plus the kitten's character class.
# Output: { is_armed, definition, texture_path } where
#   - is_armed: true iff a weapon is equipped (drives "hide weapon sprite" /
#     "fall back to unarmed attack" in callers).
#   - definition: the WeaponDefinition that owns the pose (anchor/rotation/
#     scale and attack-type for the choreographer). Picked from the weapon's
#     first allowed class so a Battle sword always reads as a Battle pose,
#     independent of the holder's class.
#   - texture_path: per-id sprite from ItemImageResolver, with the class-
#     default fallback already applied. Empty string when unarmed.

const ARMED_KEY := "is_armed"
const DEFINITION_KEY := "definition"
const TEXTURE_KEY := "texture_path"

static func resolve(weapon_item: ItemData, character_class: int) -> Dictionary:
	if weapon_item == null:
		return {
			ARMED_KEY: false,
			DEFINITION_KEY: null,
			TEXTURE_KEY: "",
		}
	var def: WeaponDefinition = null
	if not weapon_item.allowed_classes.is_empty():
		def = WeaponDefinition.for_class(weapon_item.allowed_classes[0])
	if def == null:
		def = WeaponDefinition.for_class(character_class)
	return {
		ARMED_KEY: true,
		DEFINITION_KEY: def,
		TEXTURE_KEY: ItemImageResolver.texture_path_for_item(weapon_item),
	}
