extends GutTest

func test_select_class_mage_makes_mage_with_default_name():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.MAGE)
	assert_eq(c.character_class, CharacterData.CharacterClass.MAGE)
	assert_eq(c.character_name, "Kitten")
	assert_eq(c.max_hp, 8, "mage default max_hp comes from CharacterData baseline")
	assert_eq(c.hp, c.max_hp, "new character starts at full hp")

func test_select_class_thief_uses_thief_baseline():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.THIEF)
	assert_eq(c.character_class, CharacterData.CharacterClass.THIEF)
	assert_eq(c.max_hp, 10)

func test_select_class_ninja_uses_ninja_baseline_and_custom_name():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.NINJA, "Shadow")
	assert_eq(c.character_class, CharacterData.CharacterClass.NINJA)
	assert_eq(c.character_name, "Shadow")
	assert_eq(c.max_hp, 9)

func test_select_class_returns_independent_instances():
	var a := CharacterCreation.select_class(CharacterData.CharacterClass.MAGE)
	var b := CharacterCreation.select_class(CharacterData.CharacterClass.MAGE)
	assert_ne(a.get_instance_id(), b.get_instance_id(), "each pick should return a fresh CharacterData")
	a.take_damage(3)
	assert_eq(b.hp, b.max_hp, "mutating one pick must not affect another")
