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

func test_make_new_sets_class_specific_attack_and_defense():
	var mage := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var thief := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	var ninja := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	assert_eq(mage.attack, 2)
	assert_eq(mage.defense, 0)
	assert_eq(thief.attack, 3)
	assert_eq(thief.defense, 1, "thief carries a defense baseline")
	assert_eq(ninja.attack, 4, "ninja has the highest base attack")
	assert_eq(ninja.defense, 0)

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

func test_expanded_stat_set_fields_exist():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	assert_true("magic_attack" in c)
	assert_true("magic_points" in c)
	assert_true("max_mp" in c)
	assert_true("magic_resistance" in c)
	assert_true("dexterity" in c)
	assert_true("evasion" in c)
	assert_true("crit_chance" in c)
	assert_true("luck" in c)
	assert_true("regeneration" in c)

func test_expanded_stat_set_field_types():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	assert_eq(typeof(c.evasion), TYPE_FLOAT)
	assert_eq(typeof(c.crit_chance), TYPE_FLOAT)
	assert_eq(typeof(c.magic_attack), TYPE_INT)
	assert_eq(typeof(c.magic_points), TYPE_INT)
	assert_eq(typeof(c.max_mp), TYPE_INT)
	assert_eq(typeof(c.magic_resistance), TYPE_INT)
	assert_eq(typeof(c.dexterity), TYPE_INT)
	assert_eq(typeof(c.luck), TYPE_INT)
	assert_eq(typeof(c.regeneration), TYPE_INT)

func test_make_new_sets_class_specific_magic_defaults():
	var mage := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var thief := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	assert_gt(mage.magic_attack, 0, "mage starts with non-zero magic_attack")
	assert_gt(mage.max_mp, 0, "mage starts with non-zero max_mp")
	assert_eq(mage.magic_points, mage.max_mp, "new mage starts at full mp")
	assert_gt(mage.magic_attack, thief.magic_attack, "mage out-magics thief")
	assert_gt(mage.max_mp, thief.max_mp, "mage has more mp than thief")

func test_save_load_roundtrips_expanded_stat_set():
	var tmp := "user://test_kitten_save_expanded.json"
	var c := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	c.magic_attack = 7
	c.magic_points = 4
	c.max_mp = 5
	c.magic_resistance = 2
	c.dexterity = 6
	c.evasion = 0.15
	c.crit_chance = 0.10
	c.luck = 3
	c.regeneration = 1
	var err := SaveManager.save(c, tmp)
	assert_eq(err, OK)
	var loaded := SaveManager.load(tmp)
	assert_not_null(loaded)
	var restored := CharacterData.new()
	loaded.apply_to(restored)
	assert_eq(restored.magic_attack, 7)
	assert_eq(restored.magic_points, 4)
	assert_eq(restored.max_mp, 5)
	assert_eq(restored.magic_resistance, 2)
	assert_eq(restored.dexterity, 6)
	assert_almost_eq(restored.evasion, 0.15, 0.001)
	assert_almost_eq(restored.crit_chance, 0.10, 0.001)
	assert_eq(restored.luck, 3)
	assert_eq(restored.regeneration, 1)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

func test_apply_stat_delta_increases_int_stat():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var before := c.attack
	c.apply_stat_delta("attack", 3.0)
	assert_eq(c.attack, before + 3)

func test_apply_stat_delta_decreases_int_stat():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var before := c.attack
	c.apply_stat_delta("attack", -1.0)
	assert_eq(c.attack, before - 1)

func test_apply_stat_delta_rounds_float_delta_for_int_stat():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var before := c.attack
	c.apply_stat_delta("attack", 1.7)
	assert_eq(c.attack, before + 2, "rounds to nearest, not truncates")

func test_apply_stat_delta_float_stat_stays_float():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.apply_stat_delta("evasion", 0.15)
	assert_almost_eq(c.evasion, 0.15, 0.001)
	assert_eq(typeof(c.evasion), TYPE_FLOAT)

func test_apply_stat_delta_empty_name_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var before := c.attack
	c.apply_stat_delta("", 5.0)
	assert_eq(c.attack, before)

func test_apply_stat_delta_unknown_name_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.apply_stat_delta("nonexistent_stat", 5.0)
	assert_true(true, "should not crash on unknown stat")

func test_apply_stat_delta_swap_replaces_bonus():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var base_attack := c.attack
	c.apply_stat_delta("attack", 3.0)
	assert_eq(c.attack, base_attack + 3, "old item applied")
	c.apply_stat_delta("attack", -3.0)
	c.apply_stat_delta("attack", 5.0)
	assert_eq(c.attack, base_attack + 5, "swap removes old bonus and applies new")

func test_pre_prd_save_loads_with_zero_defaults():
	var old_dict := {
		"character_name": "Kitten",
		"character_class": int(CharacterData.CharacterClass.THIEF),
		"level": 3,
		"xp": 0,
		"hp": 10,
		"max_hp": 10,
		"attack": 2,
		"defense": 0,
		"speed": 60.0,
		"skill_points": 0,
	}
	var save_data := KittenSaveData.from_dict(old_dict)
	var c := CharacterData.new()
	save_data.apply_to(c)
	assert_eq(c.magic_attack, 0)
	assert_eq(c.magic_points, 0)
	assert_eq(c.max_mp, 0)
	assert_eq(c.magic_resistance, 0)
	assert_eq(c.dexterity, 0)
	assert_almost_eq(c.evasion, 0.0, 0.001)
	assert_almost_eq(c.crit_chance, 0.0, 0.001)
	assert_eq(c.luck, 0)
	assert_eq(c.regeneration, 0)
