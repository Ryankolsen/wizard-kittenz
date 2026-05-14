extends GutTest

func test_all_items_returns_nine():
	assert_eq(ItemCatalog.all_items().size(), 9)

func test_iron_sword_content():
	var item := ItemCatalog.find("iron_sword")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.WEAPON)
	assert_eq(item.rarity, ItemData.Rarity.COMMON)
	assert_eq(item.stat_name, "attack")
	assert_eq(item.stat_bonus, 2.0)

func test_items_for_slot_armor():
	var armor := ItemCatalog.items_for_slot(ItemData.Slot.ARMOR)
	assert_eq(armor.size(), 3)
	for item in armor:
		assert_eq(item.slot, ItemData.Slot.ARMOR)

func test_items_for_rarity_epic():
	var epics := ItemCatalog.items_for_rarity(ItemData.Rarity.EPIC)
	assert_eq(epics.size(), 3)
	for item in epics:
		assert_eq(item.rarity, ItemData.Rarity.EPIC)

func test_find_unknown_returns_null():
	assert_null(ItemCatalog.find("nonexistent"))

func test_all_ids_unique():
	var ids := {}
	for item in ItemCatalog.all_items():
		assert_false(ids.has(item.id), "duplicate id %s" % item.id)
		ids[item.id] = true
