extends GutTest

# Slice 3 (PRD #250 / issue #253) — SaveSlots registry over an in-memory
# SaveBundle. Pure object tests; no autoload needed.

const SaveSlots = preload("res://scripts/core/save_slots.gd")

func _make_wizard_slot(level: int = 3, name: String = "Mittens") -> CharacterSlotData:
	var s := CharacterSlotData.new()
	s.character_name = name
	s.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	s.level = level
	return s

func test_summaries_report_occupancy():
	var bundle := SaveBundle.new()
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, _make_wizard_slot(3, "Mittens"))

	var summaries := SaveSlots.slot_summaries(bundle)
	assert_eq(summaries.size(), 4, "one entry per archetype")

	var by_arch := {}
	for entry in summaries:
		by_arch[entry["archetype"]] = entry

	var wiz: Dictionary = by_arch[SaveBundle.SLOT_WIZARD]
	assert_true(wiz["occupied"], "wizard slot should be occupied")
	assert_eq(wiz["name"], "Mittens")
	assert_eq(wiz["level"], 3)

	for arch in [SaveBundle.SLOT_BATTLE, SaveBundle.SLOT_SLEEPY, SaveBundle.SLOT_CHONK]:
		assert_false(by_arch[arch]["occupied"], "%s should be empty" % arch)

func test_new_game_reset_preserves_account():
	var bundle := SaveBundle.new()
	bundle.account.gold_balance = 500
	bundle.account.paid_class_unlocks = ["wizard_cat"]

	var occupied := _make_wizard_slot(7, "Mittens")
	occupied.unlocked_skill_ids = ["fireball", "ice_shard"]
	occupied.item_bag = ["potion_a", "potion_b"]
	bundle.set_slot(CharacterData.CharacterClass.WIZARD_KITTEN, occupied)

	SaveSlots.new_game_reset(bundle, SaveBundle.SLOT_WIZARD)

	var reset_slot: CharacterSlotData = bundle.get_slot(SaveBundle.SLOT_WIZARD)
	assert_not_null(reset_slot, "wizard slot must still exist (just freshened)")
	assert_eq(reset_slot.level, 1)
	assert_eq(reset_slot.unlocked_skill_ids.size(), 0, "skills wiped")
	assert_eq(reset_slot.item_bag.size(), 0, "item bag wiped")

	assert_eq(bundle.account.gold_balance, 500, "account gold untouched")
	assert_eq(bundle.account.paid_class_unlocks, ["wizard_cat"],
		"paid unlocks untouched")

func test_create_slot_makes_level_one_named_character():
	var slot := SaveSlots.create_slot(SaveBundle.SLOT_BATTLE, "Whiskers")
	assert_not_null(slot)
	assert_eq(slot.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(slot.character_name, "Whiskers")
	assert_eq(slot.level, 1)

func test_is_occupied_matches_get_slot():
	var bundle := SaveBundle.new()
	bundle.set_slot(CharacterData.CharacterClass.BATTLE_KITTEN, _make_wizard_slot(1, "B"))
	assert_true(SaveSlots.is_occupied(bundle, SaveBundle.SLOT_BATTLE))
	assert_false(SaveSlots.is_occupied(bundle, SaveBundle.SLOT_WIZARD))
