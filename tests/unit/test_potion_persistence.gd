extends GutTest

# PRD #358 / slice 6 (issue #364). Round-trip ConsumableInventory counts and
# PotionBelt slot assignments through SaveManager so potions survive a
# session boundary. Mirrors test_currency_ledger.gd's after_each cleanup
# of the user:// temp path.

const TMP_PATH := "user://test_potion_persistence.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func _character() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)

func test_save_load_preserves_potion_counts():
	var character := _character()
	var inv := ConsumableInventory.new()
	inv.add("health_potion", 7)
	inv.add("mana_potion", 3)
	inv.add("shield_potion", 1)
	var err := SaveManager.save(character, TMP_PATH, null, null, null, null, null, {}, null, null, null, null, 0, "", inv, null)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	var rebuilt := loaded.to_consumable_inventory()
	assert_eq(rebuilt.count_of("health_potion"), 7)
	assert_eq(rebuilt.count_of("mana_potion"), 3)
	assert_eq(rebuilt.count_of("shield_potion"), 1)

func test_save_load_preserves_belt_slot_assignments():
	var character := _character()
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	belt.assign(2, "mana_potion")
	belt.assign(3, "shield_potion")
	var err := SaveManager.save(character, TMP_PATH, null, null, null, null, null, {}, null, null, null, null, 0, "", null, belt)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	var rebuilt := loaded.to_potion_belt()
	assert_eq(rebuilt.get_slot(1), "health_potion")
	assert_eq(rebuilt.get_slot(2), "mana_potion")
	assert_eq(rebuilt.get_slot(3), "shield_potion")

func test_save_load_preserves_partial_belt_with_empty_slot():
	var character := _character()
	var belt := PotionBelt.new()
	belt.assign(1, "health_potion")
	belt.assign(3, "shield_potion")
	var err := SaveManager.save(character, TMP_PATH, null, null, null, null, null, {}, null, null, null, null, 0, "", null, belt)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_PATH)
	var rebuilt := loaded.to_potion_belt()
	assert_eq(rebuilt.get_slot(1), "health_potion")
	assert_eq(rebuilt.get_slot(2), "")
	assert_eq(rebuilt.get_slot(3), "shield_potion")

func test_empty_inventory_and_belt_round_trip_to_empty():
	var character := _character()
	var inv := ConsumableInventory.new()
	var belt := PotionBelt.new()
	var err := SaveManager.save(character, TMP_PATH, null, null, null, null, null, {}, null, null, null, null, 0, "", inv, belt)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_PATH)
	var inv_back := loaded.to_consumable_inventory()
	assert_eq(inv_back.count_of("health_potion"), 0)
	assert_eq(inv_back.count_of("mana_potion"), 0)
	var belt_back := loaded.to_potion_belt()
	assert_eq(belt_back.get_slot(1), "")
	assert_eq(belt_back.get_slot(2), "")
	assert_eq(belt_back.get_slot(3), "")

func test_unknown_potion_id_in_inventory_dropped_on_load():
	# Simulate a save written against an older catalog: counts include a potion
	# id that's no longer in PotionCatalog. to_consumable_inventory filters it.
	var s := KittenSaveData.new()
	s.consumable_inventory_data = {
		"health_potion": 4,
		"ghost_potion": 9,
	}
	var rebuilt := s.to_consumable_inventory()
	assert_eq(rebuilt.count_of("health_potion"), 4)
	assert_eq(rebuilt.count_of("ghost_potion"), 0)

func test_unknown_potion_id_in_belt_dropped_on_load():
	var s := KittenSaveData.new()
	s.potion_belt_slots = ["ghost_potion", "mana_potion", ""]
	var belt := s.to_potion_belt()
	assert_eq(belt.get_slot(1), "")
	assert_eq(belt.get_slot(2), "mana_potion")
	assert_eq(belt.get_slot(3), "")

func test_legacy_save_without_potion_fields_round_trips_empty():
	# A save predating slice 6 has neither key; from_dict + helpers should
	# yield an empty inventory and an empty belt rather than null/garbage.
	var s := KittenSaveData.from_dict({"character_name": "Legacy"})
	var inv := s.to_consumable_inventory()
	assert_eq(inv.count_of("health_potion"), 0)
	var belt := s.to_potion_belt()
	assert_eq(belt.get_slot(1), "")
	assert_eq(belt.get_slot(2), "")
	assert_eq(belt.get_slot(3), "")
