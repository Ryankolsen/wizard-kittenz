extends GutTest

func test_equip_into_empty_slot():
	var inv := ItemInventory.new()
	var iron_sword := ItemCatalog.find("iron_sword")
	inv.equip(iron_sword)
	assert_eq(inv.equipped_in(ItemData.Slot.WEAPON), iron_sword)
	assert_eq(inv.bag_items().size(), 0)

func test_slot_displacement_moves_old_to_bag():
	var inv := ItemInventory.new()
	var iron := ItemCatalog.find("iron_sword")
	var silver := ItemCatalog.find("silver_sword")
	inv.equip(iron)
	inv.equip(silver)
	assert_eq(inv.equipped_in(ItemData.Slot.WEAPON), silver)
	assert_eq(inv.bag_items().size(), 1)
	assert_eq(inv.bag_items()[0], iron)

func test_unequip_moves_to_bag():
	var inv := ItemInventory.new()
	var iron := ItemCatalog.find("iron_sword")
	inv.equip(iron)
	inv.unequip(ItemData.Slot.WEAPON)
	assert_null(inv.equipped_in(ItemData.Slot.WEAPON))
	assert_eq(inv.bag_items().size(), 1)
	assert_eq(inv.bag_items()[0], iron)

func test_add_to_bag_leaves_slots_untouched():
	var inv := ItemInventory.new()
	var charm := ItemCatalog.find("lucky_charm")
	inv.add_to_bag(charm)
	assert_null(inv.equipped_in(ItemData.Slot.WEAPON))
	assert_null(inv.equipped_in(ItemData.Slot.ARMOR))
	assert_null(inv.equipped_in(ItemData.Slot.ACCESSORY))
	assert_eq(inv.bag_items().size(), 1)
	assert_eq(inv.bag_items()[0], charm)

func test_loadout_changed_signal_fires_on_equip_and_unequip():
	var inv := ItemInventory.new()
	watch_signals(inv)
	var iron := ItemCatalog.find("iron_sword")
	inv.equip(iron)
	assert_signal_emit_count(inv, "loadout_changed", 1)
	inv.unequip(ItemData.Slot.WEAPON)
	assert_signal_emit_count(inv, "loadout_changed", 2)

func test_remove_from_bag_by_id():
	var inv := ItemInventory.new()
	var iron := ItemCatalog.find("iron_sword")
	var charm := ItemCatalog.find("lucky_charm")
	inv.add_to_bag(iron)
	inv.add_to_bag(charm)
	inv.remove_from_bag("iron_sword")
	assert_eq(inv.bag_items().size(), 1)
	assert_eq(inv.bag_items()[0], charm)

func test_bag_is_unbounded():
	var inv := ItemInventory.new()
	var iron := ItemCatalog.find("iron_sword")
	for i in 20:
		inv.add_to_bag(iron)
	assert_eq(inv.bag_items().size(), 20)
