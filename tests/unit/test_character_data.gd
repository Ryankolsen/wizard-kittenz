extends GutTest

const TMP_PATH := "user://test_character.tres"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func test_make_new_mage_has_expected_defaults():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers")
	assert_eq(c.character_name, "Whiskers")
	assert_eq(c.character_class, CharacterData.CharacterClass.MAGE)
	assert_eq(c.level, 1)
	assert_eq(c.xp, 0)
	assert_eq(c.max_hp, 8, "mage starts with 8 max hp")
	assert_eq(c.hp, c.max_hp, "new character starts at full hp")

func test_make_new_thief_and_ninja_have_class_specific_hp():
	var thief := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	var ninja := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	assert_eq(thief.max_hp, 10)
	assert_eq(ninja.max_hp, 9)

func test_max_hp_scales_with_level():
	assert_eq(CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 1), 8)
	assert_eq(CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 2), 10)
	assert_eq(CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 5), 16)

func test_take_damage_reduces_hp_and_clamps_at_zero():
	var c := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	assert_eq(c.take_damage(3), 3)
	assert_eq(c.hp, 7)
	assert_true(c.is_alive())
	assert_eq(c.take_damage(99), 7, "overkill returns only damage actually dealt")
	assert_eq(c.hp, 0)
	assert_false(c.is_alive())

func test_heal_increases_hp_and_clamps_at_max():
	var c := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	c.take_damage(8)
	assert_eq(c.hp, 2)
	assert_eq(c.heal(3), 3)
	assert_eq(c.hp, 5)
	assert_eq(c.heal(99), 5, "overheal returns only healing actually applied")
	assert_eq(c.hp, c.max_hp)

func test_save_and_load_roundtrips_state():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Shadow")
	c.xp = 42
	c.take_damage(3)
	var err := c.save_to(TMP_PATH)
	assert_eq(err, OK, "save should succeed")

	var loaded := CharacterData.load_from(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.character_name, "Shadow")
	assert_eq(loaded.character_class, CharacterData.CharacterClass.NINJA)
	assert_eq(loaded.xp, 42)
	assert_eq(loaded.hp, c.hp)
	assert_eq(loaded.max_hp, c.max_hp)

func test_load_from_missing_path_returns_null():
	assert_null(CharacterData.load_from("user://does_not_exist.tres"))
