extends GutTest

# SaveManager + ItemInventory wiring (PRD #73 / issue #81). Round-trips
# equipped items and bag contents through SaveManager.save / SaveManager.load,
# and verifies stat rehydration via ItemStatApplicator after load.

const ItemStatApplicatorRef = preload("res://scripts/item_stat_applicator.gd")

const TMP_PATH := "user://test_save_items.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func _make_character() -> CharacterData:
	var c := CharacterData.new()
	c.character_name = "Whiskers"
	c.character_class = 0
	c.level = 1
	c.max_hp = 10
	c.hp = 10
	c.attack = 5
	c.defense = 1
	c.speed = 1.0
	return c

func test_save_load_round_trips_equipped_weapon():
	var c := _make_character()
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	var err := SaveManager.save(c, TMP_PATH, null, null, null, null, null, {}, null, null, inv)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	var restored := loaded.to_item_inventory()
	assert_eq(restored.equipped_in(ItemData.Slot.WEAPON).id, "iron_sword")

func test_stat_rehydration_applies_item_bonus_after_load():
	var c := _make_character()
	var base_attack := c.attack
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	SaveManager.save(c, TMP_PATH, null, null, null, null, null, {}, null, null, inv)
	var loaded := SaveManager.load(TMP_PATH)
	var restored_char := CharacterData.new()
	loaded.apply_to(restored_char)
	var restored_inv := loaded.to_item_inventory()
	ItemStatApplicatorRef.apply(restored_inv, restored_char)
	assert_eq(restored_char.attack, base_attack + 2)

func test_bag_contents_survive_round_trip():
	var c := _make_character()
	var inv := ItemInventory.new()
	inv.add_to_bag(ItemCatalog.find("lucky_charm"))
	SaveManager.save(c, TMP_PATH, null, null, null, null, null, {}, null, null, inv)
	var restored := SaveManager.load(TMP_PATH).to_item_inventory()
	assert_eq(restored.bag_items().size(), 1)
	assert_eq(restored.bag_items()[0].id, "lucky_charm")

func test_legacy_save_with_no_item_fields_loads_empty_inventory():
	var c := _make_character()
	SaveManager.save(c, TMP_PATH)
	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	var inv := loaded.to_item_inventory()
	assert_null(inv.equipped_in(ItemData.Slot.WEAPON))
	assert_null(inv.equipped_in(ItemData.Slot.ARMOR))
	assert_null(inv.equipped_in(ItemData.Slot.ACCESSORY))
	assert_eq(inv.bag_items().size(), 0)

func test_null_item_inventory_param_does_not_crash():
	var c := _make_character()
	var err := SaveManager.save(c, TMP_PATH, null, null, null, null, null, {}, null, null, null)
	assert_eq(err, OK)
