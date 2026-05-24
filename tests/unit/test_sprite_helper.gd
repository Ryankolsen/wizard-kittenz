extends GutTest

# Slice 2 (PRD #223 / issue #225): wizard kitten swapped to the weaponless
# _right sprite so the WeaponPivot's wand renders independently. The legacy
# wizard_kitten.png is now the cat-tier fallback only.
const WIZARD_PATH := "res://assets/sprites/wizard_kitten_right.png"
const BATTLE_PATH := "res://assets/sprites/battle_kitten_right.png"
const SLEEPY_PATH := "res://assets/sprites/sleepy_kitten_right.png"
const CHONK_PATH := "res://assets/sprites/chonk_kitten_left.png"

func test_battle_kitten_path():
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.BATTLE_KITTEN), BATTLE_PATH)

func test_wizard_kitten_path():
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.WIZARD_KITTEN), WIZARD_PATH)

func test_sleepy_kitten_path():
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.SLEEPY_KITTEN), SLEEPY_PATH)

func test_chonk_kitten_path():
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.CHONK_KITTEN), CHONK_PATH)

func test_cat_tier_falls_back_to_wizard_kitten():
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.BATTLE_CAT), WIZARD_PATH)
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.WIZARD_CAT), WIZARD_PATH)
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.SLEEPY_CAT), WIZARD_PATH)
	assert_eq(SpriteHelper.path_for_class(CharacterData.CharacterClass.CHONK_CAT), WIZARD_PATH)

func test_faces_left_only_for_chonk():
	# Chonk's sprite asset faces left so the flip logic is inverted for it.
	assert_true(SpriteHelper.faces_left(CharacterData.CharacterClass.CHONK_KITTEN))
	assert_false(SpriteHelper.faces_left(CharacterData.CharacterClass.WIZARD_KITTEN))
	assert_false(SpriteHelper.faces_left(CharacterData.CharacterClass.BATTLE_KITTEN))
	assert_false(SpriteHelper.faces_left(CharacterData.CharacterClass.SLEEPY_KITTEN))
	assert_false(SpriteHelper.faces_left(CharacterData.CharacterClass.CHONK_CAT))

func test_returned_paths_load_as_textures():
	for cc in [
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
		CharacterData.CharacterClass.BATTLE_CAT,
	]:
		var path := SpriteHelper.path_for_class(cc)
		assert_ne(path, "", "non-empty path")
		var tex := load(path)
		assert_not_null(tex, "texture loads at %s" % path)
