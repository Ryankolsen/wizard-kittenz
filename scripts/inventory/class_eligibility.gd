class_name ClassEligibility
extends RefCounted

# Pure helper for "can this character class use this item". Cat-tier classes
# inherit eligibility from their Kitten counterpart so we only tag the Kitten
# class on each item.

const _CAT_TO_KITTEN := {
	CharacterData.CharacterClass.BATTLE_CAT: CharacterData.CharacterClass.BATTLE_KITTEN,
	CharacterData.CharacterClass.WIZARD_CAT: CharacterData.CharacterClass.WIZARD_KITTEN,
	CharacterData.CharacterClass.SLEEPY_CAT: CharacterData.CharacterClass.SLEEPY_KITTEN,
	CharacterData.CharacterClass.CHONK_CAT: CharacterData.CharacterClass.CHONK_KITTEN,
}

static func is_class_allowed(item: ItemData, character_class: int) -> bool:
	if item == null:
		return false
	if item.allowed_classes.is_empty():
		return false
	if item.allowed_classes.has(character_class):
		return true
	if _CAT_TO_KITTEN.has(character_class):
		return item.allowed_classes.has(_CAT_TO_KITTEN[character_class])
	return false
