extends GutTest

func _make_character() -> CharacterData:
	var c := CharacterData.new()
	c.character_name = "Whiskers"
	c.character_class = 0
	c.level = 1
	c.max_hp = 10
	c.hp = 10
	c.attack = 1
	c.defense = 1
	c.speed = 1.0
	return c

func test_to_dict_includes_item_keys():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	inv.add_to_bag(ItemCatalog.find("lucky_charm"))
	var s := KittenSaveData.from_character(_make_character(), null, null, null, null, null, {}, null, null, inv)
	var d := s.to_dict()
	assert_true(d.has("equipped_items"))
	assert_true(d.has("item_bag"))
	assert_eq(d["equipped_items"][int(ItemData.Slot.WEAPON)], "iron_sword")
	assert_eq((d["item_bag"] as Array).size(), 1)
	assert_eq(String((d["item_bag"] as Array)[0]), "lucky_charm")

func test_round_trip_restores_inventory():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	inv.add_to_bag(ItemCatalog.find("lucky_charm"))
	var s := KittenSaveData.from_character(_make_character(), null, null, null, null, null, {}, null, null, inv)
	var restored := KittenSaveData.from_dict(s.to_dict())
	var restored_inv := restored.to_item_inventory()
	assert_eq(restored_inv.equipped_in(ItemData.Slot.WEAPON).id, "iron_sword")
	assert_eq(restored_inv.bag_items().size(), 1)
	assert_eq(restored_inv.bag_items()[0].id, "lucky_charm")

func test_legacy_save_no_item_keys():
	var s := KittenSaveData.from_dict({})
	assert_eq(s.equipped_items, {})
	assert_eq(s.item_bag, [])
	var inv := s.to_item_inventory()
	assert_null(inv.equipped_in(ItemData.Slot.WEAPON))
	assert_null(inv.equipped_in(ItemData.Slot.ARMOR))
	assert_null(inv.equipped_in(ItemData.Slot.ACCESSORY))
	assert_eq(inv.bag_items().size(), 0)

func test_unknown_id_silently_dropped():
	var s := KittenSaveData.from_dict({"item_bag": ["does_not_exist"]})
	var inv := s.to_item_inventory()
	assert_eq(inv.bag_items().size(), 0)

func test_all_three_slots_round_trip():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	inv.equip(ItemCatalog.find("leather_vest"))
	inv.equip(ItemCatalog.find("lucky_charm"))
	var s := KittenSaveData.from_character(_make_character(), null, null, null, null, null, {}, null, null, inv)
	var restored_inv := KittenSaveData.from_dict(s.to_dict()).to_item_inventory()
	assert_eq(restored_inv.equipped_in(ItemData.Slot.WEAPON).id, "iron_sword")
	assert_eq(restored_inv.equipped_in(ItemData.Slot.ARMOR).id, "leather_vest")
	assert_eq(restored_inv.equipped_in(ItemData.Slot.ACCESSORY).id, "lucky_charm")
	assert_eq(restored_inv.bag_items().size(), 0)
