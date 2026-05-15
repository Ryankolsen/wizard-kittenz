extends GutTest

# Equipment panel inside the pause menu Character → Inventory tab
# (PRD #73 / issue #82). Verifies refresh() renders three slot rows and
# a bag list, that pressing equip / unequip mutates ItemInventory, and
# that CharacterData stats track the bonus delta.

const EquipmentTabPanelScript := preload("res://scripts/ui/equipment_tab_panel.gd")

func _make_panel() -> EquipmentTabPanel:
	var p := EquipmentTabPanel.new()
	add_child_autofree(p)
	return p

func _make_char() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")

func test_refresh_renders_three_slot_rows_when_empty():
	var inv := ItemInventory.new()
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	for slot in [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.ACCESSORY]:
		var label := panel.find_child("SlotLabel_%d" % slot, true, false) as Button
		assert_not_null(label, "slot %d label must exist" % slot)
		assert_true(label.text.to_lower().contains("empty"),
			"empty slot %d must read 'Empty'" % slot)

func test_equipped_slot_row_shows_name_and_rarity():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("silver_sword"))
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var label := panel.find_child("SlotLabel_%d" % ItemData.Slot.WEAPON, true, false) as Button
	assert_not_null(label)
	assert_true(label.text.contains("Silver Sword"), "weapon row must show item name")
	assert_true(label.text.contains("Rare"), "weapon row must show rarity")

func test_bag_items_render_with_equip_button():
	var inv := ItemInventory.new()
	inv.add_to_bag(ItemCatalog.find("iron_sword"))
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var btn := panel.find_child("EquipButton_0", true, false) as Button
	assert_not_null(btn, "bag row 0 must have an Equip button")

func test_equip_from_bag_moves_to_slot_and_applies_stat():
	var inv := ItemInventory.new()
	inv.add_to_bag(ItemCatalog.find("iron_sword"))
	var c := _make_char()
	var base_attack := c.attack
	var panel := _make_panel()
	panel.refresh(inv, c)
	var btn := panel.find_child("EquipButton_0", true, false) as Button
	btn.pressed.emit()
	assert_eq(inv.equipped_in(ItemData.Slot.WEAPON).id, "iron_sword",
		"iron_sword must be equipped in WEAPON slot")
	assert_eq(inv.bag_items().size(), 0, "bag must be empty after equipping")
	assert_eq(c.attack, base_attack + 2, "attack must increase by item bonus")

func test_equip_swap_displaces_prev_to_bag_and_replaces_stat():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	inv.add_to_bag(ItemCatalog.find("silver_sword"))
	var c := _make_char()
	# Apply the currently-equipped iron sword bonus so the panel's swap math
	# starts from a realistic equipped state.
	ItemStatApplicator.apply(inv, c)
	var attack_after_iron := c.attack
	var panel := _make_panel()
	panel.refresh(inv, c)
	var btn := panel.find_child("EquipButton_0", true, false) as Button
	btn.pressed.emit()
	assert_eq(inv.equipped_in(ItemData.Slot.WEAPON).id, "silver_sword")
	var bag := inv.bag_items()
	assert_eq(bag.size(), 1, "displaced iron_sword must be in bag")
	assert_eq(bag[0].id, "iron_sword")
	# iron_sword (+2) → silver_sword (+5): delta is +3 from the
	# post-iron-equip baseline.
	assert_eq(c.attack, attack_after_iron + 3,
		"attack must track the swap delta")

func test_tap_slot_reveals_unequip_then_unequip_clears_slot():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	var c := _make_char()
	ItemStatApplicator.apply(inv, c)
	var base_attack := c.attack - 2  # post-equip
	var panel := _make_panel()
	panel.refresh(inv, c)
	var label := panel.find_child("SlotLabel_%d" % ItemData.Slot.WEAPON, true, false) as Button
	label.pressed.emit()
	var unequip := panel.find_child("UnequipButton_%d" % ItemData.Slot.WEAPON, true, false) as Button
	assert_not_null(unequip, "tapping slot row must reveal Unequip button")
	unequip.pressed.emit()
	assert_eq(inv.equipped_in(ItemData.Slot.WEAPON), null,
		"unequip must clear the slot")
	assert_eq(inv.bag_items().size(), 1, "unequipped item must move to bag")
	assert_eq(inv.bag_items()[0].id, "iron_sword")
	assert_eq(c.attack, base_attack, "stat must roll back to pre-equip baseline")

func test_empty_slot_row_is_disabled():
	var inv := ItemInventory.new()
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var label := panel.find_child("SlotLabel_%d" % ItemData.Slot.WEAPON, true, false) as Button
	assert_not_null(label)
	assert_true(label.disabled, "empty slot row must be disabled (no unequip target)")

func test_null_inventory_does_not_crash():
	var panel := _make_panel()
	panel.refresh(null, _make_char())
	assert_not_null(panel.find_child("Section_Equipped", true, false),
		"sections must still render with a null inventory")
