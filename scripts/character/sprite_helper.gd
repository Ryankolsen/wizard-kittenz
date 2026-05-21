class_name SpriteHelper
extends RefCounted

const _WIZARD_KITTEN_PATH := "res://assets/sprites/wizard_kitten.png"
const _BATTLE_KITTEN_PATH := "res://assets/sprites/battle_kitten_right.png"
const _SLEEPY_KITTEN_PATH := "res://assets/sprites/sleepy_kitten_right.png"
const _CHONK_KITTEN_PATH := "res://assets/sprites/chonk_kitten_left.png"

# Returns true when the sprite asset faces LEFT (so the flip logic should be
# inverted — flip when moving right, not left).
static func faces_left(cc: CharacterData.CharacterClass) -> bool:
	return cc == CharacterData.CharacterClass.CHONK_KITTEN

# Cat-tier classes have no art yet — fall back to wizard kitten so the renderer
# still gets a valid texture instead of crashing on a missing asset.
static func path_for_class(cc: CharacterData.CharacterClass) -> String:
	match cc:
		CharacterData.CharacterClass.BATTLE_KITTEN:
			return _BATTLE_KITTEN_PATH
		CharacterData.CharacterClass.SLEEPY_KITTEN:
			return _SLEEPY_KITTEN_PATH
		CharacterData.CharacterClass.CHONK_KITTEN:
			return _CHONK_KITTEN_PATH
		_:
			return _WIZARD_KITTEN_PATH
