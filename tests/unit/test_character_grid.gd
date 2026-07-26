extends GutTest

# Slice 4 (PRD #250 / issue #254) — testable bits of the character-select
# grid + name-only customize flow. Scene wiring lives in
# character_creation.gd / .tscn; this file covers the extractable helpers.

const CharacterGrid = preload("res://scripts/character/character_grid.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")

func _wizard_slot(level: int, name: String) -> CharacterSlotData:
	var s := CharacterSlotData.new()
	s.character_name = name
	s.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	s.level = level
	return s

func test_card_label_for_occupied_and_empty():
	var bundle := SaveBundle.new()
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, _wizard_slot(4, "Mittens"))
	var summaries := SaveSlots.slot_summaries(bundle)
	var by_arch := {}
	for entry in summaries:
		by_arch[entry["archetype"]] = entry
	assert_eq(CharacterGrid.card_label(by_arch[SaveBundle.SLOT_WIZARD]), "Mittens · Lv 4")
	assert_eq(CharacterGrid.card_label(by_arch[SaveBundle.SLOT_BATTLE]), "New")
	assert_eq(CharacterGrid.card_label(by_arch[SaveBundle.SLOT_SLEEPY]), "New")
	assert_eq(CharacterGrid.card_label(by_arch[SaveBundle.SLOT_CHONK]), "New")

func test_class_display_name_humanizes_enum():
	assert_eq(CharacterGrid.class_display_name(CharacterData.CharacterClass.WIZARD_KITTEN), "Wizard Kitten")
	assert_eq(CharacterGrid.class_display_name(CharacterData.CharacterClass.CHONK_KITTEN), "Chonk Kitten")

func test_card_lines_for_occupied_slot():
	var bundle := SaveBundle.new()
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, _wizard_slot(4, "Mittens"))
	var summaries := SaveSlots.slot_summaries(bundle)
	var by_arch := {}
	for entry in summaries:
		by_arch[entry["archetype"]] = entry
	var wiz: Dictionary = by_arch[SaveBundle.SLOT_WIZARD]
	assert_eq(CharacterGrid.card_name_text(wiz), "Mittens")
	assert_eq(CharacterGrid.card_class_text(wiz), "Wizard Kitten")
	assert_eq(CharacterGrid.card_level_text(wiz), "Lv 4")

func test_card_lines_for_empty_slot():
	var bundle := SaveBundle.new()
	var summaries := SaveSlots.slot_summaries(bundle)
	var by_arch := {}
	for entry in summaries:
		by_arch[entry["archetype"]] = entry
	var battle: Dictionary = by_arch[SaveBundle.SLOT_BATTLE]
	assert_eq(CharacterGrid.card_name_text(battle), "New Game",
		"empty slot's name line is the New Game prompt")
	assert_eq(CharacterGrid.card_class_text(battle), "Battle Kitten",
		"empty slot still advertises its class")
	assert_eq(CharacterGrid.card_level_text(battle), "",
		"empty slot has no level line")

func test_card_portrait_path_returns_kitten_path_for_default_class():
	var bundle := SaveBundle.new()
	var summaries := SaveSlots.slot_summaries(bundle)
	var by_arch := {}
	for entry in summaries:
		by_arch[entry["archetype"]] = entry
	assert_eq(
		CharacterGrid.card_portrait_path(by_arch[SaveBundle.SLOT_BATTLE]),
		SpriteHelper.path_for_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	)

func test_card_portrait_path_per_class_value():
	var expectations := {
		CharacterData.CharacterClass.BATTLE_KITTEN: "res://assets/sprites/battle_kitten_right.png",
		CharacterData.CharacterClass.WIZARD_KITTEN: "res://assets/sprites/wizard_kitten_right.png",
		CharacterData.CharacterClass.SLEEPY_KITTEN: "res://assets/sprites/sleepy_kitten_right.png",
		CharacterData.CharacterClass.CHONK_KITTEN: "res://assets/sprites/chonk_kitten_right.png",
		CharacterData.CharacterClass.BATTLE_CAT: "res://assets/sprites/battle_cat_right.png",
		CharacterData.CharacterClass.WIZARD_CAT: "res://assets/sprites/wizard_cat_right.png",
		CharacterData.CharacterClass.SLEEPY_CAT: "res://assets/sprites/sleepy_cat_right.png",
		CharacterData.CharacterClass.CHONK_CAT: "res://assets/sprites/chonk_cat_right.png",
	}
	for klass in expectations:
		var path: String = CharacterGrid.card_portrait_path({"class": klass})
		assert_eq(path, expectations[klass])
		assert_true(ResourceLoader.exists(path), "sprite must exist: " + path)

func test_card_portrait_path_falls_back_for_missing_class_field():
	assert_eq(
		CharacterGrid.card_portrait_path({}),
		SpriteHelper.path_for_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	)

func test_customize_produces_named_character_default_appearance():
	var slot := CharacterGrid.customize_create_slot(SaveBundle.SLOT_BATTLE, "Whiskers")
	assert_not_null(slot)
	assert_eq(slot.character_name, "Whiskers")
	assert_eq(slot.appearance_index, 0,
		"name-only customize must leave appearance at default 0")
	assert_eq(slot.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(slot.level, 1)

func test_new_game_handler_resets_only_slot():
	var bundle := SaveBundle.new()
	bundle.account.gold_balance = 250
	var occupied := _wizard_slot(7, "Mittens")
	occupied.unlocked_skill_ids = ["fireball"]
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, occupied)

	CharacterGrid.confirm_new_game(bundle, SaveBundle.SLOT_WIZARD)

	var reset_slot: CharacterSlotData = bundle.get_slot(SaveBundle.SLOT_WIZARD)
	assert_not_null(reset_slot)
	assert_eq(reset_slot.level, 1, "wizard slot is reset to level 1")
	assert_eq(reset_slot.unlocked_skill_ids.size(), 0, "wizard skills wiped")
	assert_eq(bundle.account.gold_balance, 250,
		"account-wide gold preserved across new-game reset")
