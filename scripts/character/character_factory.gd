class_name CharacterFactory
extends RefCounted

# String-keyed front door for spawning a starting CharacterData. Lets call sites
# (UI buttons, debug spawners, save migrations against a class-name string)
# stay agnostic of the CharacterClass enum's integer values. CharacterData
# already exposes make_new(klass, name); this layer just resolves the name.

# Class-name -> CharacterClass enum mapping. Lowercase-folded so case mistakes
# from UI bindings don't bite. Unknown names fall through to BATTLE_KITTEN
# (default starter class) rather than asserting — better UX for an external
# save with a typo than a crash.
static func class_from_name(class_name_str: String) -> int:
	match class_name_str.to_lower():
		"battle_kitten": return CharacterData.CharacterClass.BATTLE_KITTEN
		"wizard_kitten": return CharacterData.CharacterClass.WIZARD_KITTEN
		"sleepy_kitten": return CharacterData.CharacterClass.SLEEPY_KITTEN
		"chonk_kitten": return CharacterData.CharacterClass.CHONK_KITTEN
		"battle_cat": return CharacterData.CharacterClass.BATTLE_CAT
		"wizard_cat": return CharacterData.CharacterClass.WIZARD_CAT
		"sleepy_cat": return CharacterData.CharacterClass.SLEEPY_CAT
		"chonk_cat": return CharacterData.CharacterClass.CHONK_CAT
	return CharacterData.CharacterClass.BATTLE_KITTEN

# Inverse lookup: enum int -> the lowercase id used by UnlockRegistry /
# MetaProgressionTracker. Centralising the mapping here keeps the
# tracker call sites from string-folding their own enum names.
static func name_from_class(klass: int) -> String:
	match klass:
		CharacterData.CharacterClass.BATTLE_KITTEN: return "battle_kitten"
		CharacterData.CharacterClass.WIZARD_KITTEN: return "wizard_kitten"
		CharacterData.CharacterClass.SLEEPY_KITTEN: return "sleepy_kitten"
		CharacterData.CharacterClass.CHONK_KITTEN: return "chonk_kitten"
		CharacterData.CharacterClass.BATTLE_CAT: return "battle_cat"
		CharacterData.CharacterClass.WIZARD_CAT: return "wizard_cat"
		CharacterData.CharacterClass.SLEEPY_CAT: return "sleepy_cat"
		CharacterData.CharacterClass.CHONK_CAT: return "chonk_cat"
	return "battle_kitten"

static func create_default(class_name_str: String, character_name: String = "Kitten") -> CharacterData:
	var klass: int = class_from_name(class_name_str)
	return CharacterData.make_new(klass, character_name)
