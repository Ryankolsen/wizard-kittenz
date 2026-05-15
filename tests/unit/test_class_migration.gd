extends GutTest

# Save migration (issue #120). Legacy saves stored CharacterClass enum ints
# 0-5 (MAGE/THIEF/NINJA/ARCHMAGE/MASTER_THIEF/SHADOW_NINJA). After the
# Kitten class system (PRD #117) those ints no longer point to valid
# classes, so KittenSaveData.from_dict must remap them to the closest
# Kitten archetype.

func test_old_mage_migrates_to_wizard_kitten() -> void:
	var s := KittenSaveData.from_dict({"character_class": 0})
	assert_eq(s.character_class, CharacterData.CharacterClass.WIZARD_KITTEN)

func test_old_thief_migrates_to_battle_kitten() -> void:
	var s := KittenSaveData.from_dict({"character_class": 1})
	assert_eq(s.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)

func test_old_ninja_migrates_to_battle_kitten() -> void:
	var s := KittenSaveData.from_dict({"character_class": 2})
	assert_eq(s.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)

func test_old_archmage_migrates_to_wizard_cat() -> void:
	var s := KittenSaveData.from_dict({"character_class": 3})
	assert_eq(s.character_class, CharacterData.CharacterClass.WIZARD_CAT)

func test_old_master_thief_migrates_to_battle_cat() -> void:
	var s := KittenSaveData.from_dict({"character_class": 4})
	assert_eq(s.character_class, CharacterData.CharacterClass.BATTLE_CAT)

func test_old_shadow_ninja_migrates_to_battle_cat() -> void:
	var s := KittenSaveData.from_dict({"character_class": 5})
	assert_eq(s.character_class, CharacterData.CharacterClass.BATTLE_CAT)

func test_new_battle_kitten_passes_through_unchanged() -> void:
	var s := KittenSaveData.from_dict({
		"character_class": int(CharacterData.CharacterClass.BATTLE_KITTEN),
	})
	assert_eq(s.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)

func test_new_chonk_cat_passes_through_unchanged() -> void:
	var s := KittenSaveData.from_dict({
		"character_class": int(CharacterData.CharacterClass.CHONK_CAT),
	})
	assert_eq(s.character_class, CharacterData.CharacterClass.CHONK_CAT)

func test_unknown_class_falls_back_to_battle_kitten() -> void:
	var s := KittenSaveData.from_dict({"character_class": 99})
	assert_eq(s.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)

func test_migrated_character_applies_cleanly() -> void:
	# AC: "Character is not null and stats are valid after migration"
	var s := KittenSaveData.from_dict({
		"character_class": 0,
		"character_name": "Legacy",
		"level": 5,
		"max_hp": 20,
		"hp": 20,
	})
	var c := CharacterData.new()
	s.apply_to(c)
	assert_eq(c.character_class, CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(c.character_name, "Legacy")
	assert_eq(c.level, 5)
