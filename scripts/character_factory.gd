class_name CharacterFactory
extends RefCounted

# String-keyed front door for spawning a starting CharacterData. Lets call sites
# (UI buttons, debug spawners, save migrations against a class-name string)
# stay agnostic of the CharacterClass enum's integer values. CharacterData
# already exposes make_new(klass, name); this layer just resolves the name.

# Class-name -> CharacterClass enum mapping. Lowercase-folded so case mistakes
# from UI bindings don't bite. Unknown names fall through to MAGE (default
# starter class) rather than asserting — better UX for an external save with
# a typo than a crash.
static func class_from_name(class_name_str: String) -> int:
	match class_name_str.to_lower():
		"mage": return CharacterData.CharacterClass.MAGE
		"thief": return CharacterData.CharacterClass.THIEF
		"ninja": return CharacterData.CharacterClass.NINJA
	return CharacterData.CharacterClass.MAGE

static func create_default(class_name_str: String, character_name: String = "Kitten") -> CharacterData:
	var klass: int = class_from_name(class_name_str)
	return CharacterData.make_new(klass, character_name)
