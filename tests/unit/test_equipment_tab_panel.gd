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

func test_refresh_renders_three_slot_tiles_when_empty():
	var inv := ItemInventory.new()
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	for slot in [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.ACCESSORY]:
		var tile := panel.find_child("SlotTile_%d" % slot, true, false) as Button
		assert_not_null(tile, "slot %d tile must exist" % slot)
		assert_true(tile.tooltip_text.to_lower().contains("empty"),
			"empty slot %d tooltip must read 'Empty'" % slot)

func test_equipped_slot_tile_tooltip_shows_name_and_rarity():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("silver_sword"))
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var tile := panel.find_child("SlotTile_%d" % ItemData.Slot.WEAPON, true, false) as Button
	assert_not_null(tile)
	assert_true(tile.tooltip_text.contains("Alley-Cat Cutlass"), "weapon tile tooltip must show item name")
	assert_true(tile.tooltip_text.contains("Rare"), "weapon tile tooltip must show rarity")

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
	var tile := panel.find_child("SlotTile_%d" % ItemData.Slot.WEAPON, true, false) as Button
	tile.pressed.emit()
	var unequip := panel.find_child("UnequipButton_%d" % ItemData.Slot.WEAPON, true, false) as Button
	assert_not_null(unequip, "tapping slot tile must reveal Unequip button")
	unequip.pressed.emit()
	assert_eq(inv.equipped_in(ItemData.Slot.WEAPON), null,
		"unequip must clear the slot")
	assert_eq(inv.bag_items().size(), 1, "unequipped item must move to bag")
	assert_eq(inv.bag_items()[0].id, "iron_sword")
	assert_eq(c.attack, base_attack, "stat must roll back to pre-equip baseline")

func test_empty_slot_tile_is_disabled():
	var inv := ItemInventory.new()
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var tile := panel.find_child("SlotTile_%d" % ItemData.Slot.WEAPON, true, false) as Button
	assert_not_null(tile)
	assert_true(tile.disabled, "empty slot tile must be disabled (no unequip target)")

func test_equipped_weapon_row_shows_thumbnail():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var thumb := panel.find_child("SlotThumb_%d" % ItemData.Slot.WEAPON, true, false) as TextureRect
	assert_not_null(thumb, "equipped weapon row must include a thumbnail node")
	assert_not_null(thumb.texture, "thumbnail texture must be set")
	assert_eq(thumb.texture.resource_path, "res://assets/sprites/weapon_slippery_mackerel.png")

func test_bag_weapon_row_shows_thumbnail():
	var inv := ItemInventory.new()
	inv.add_to_bag(ItemCatalog.find("apprentice_wand"))
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Test")
	var panel := _make_panel()
	panel.refresh(inv, c)
	var thumb := panel.find_child("BagThumb_0", true, false) as TextureRect
	assert_not_null(thumb, "bag weapon row must include a thumbnail node")
	assert_not_null(thumb.texture)
	assert_eq(thumb.texture.resource_path, "res://assets/sprites/weapon_birthday_sparkler.png")

func test_armor_row_shows_rarity_tier_thumbnail():
	# PRD #288 / issue #290: armor/accessory rows now render a rarity-tier
	# sprite via ItemImageResolver. chain_mail is RARE → armor_rare.png.
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("chain_mail"))
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var thumb := panel.find_child("SlotThumb_%d" % ItemData.Slot.ARMOR, true, false) as TextureRect
	assert_not_null(thumb, "armor row must include a thumbnail node")
	assert_not_null(thumb.texture, "armor thumbnail texture must be set")
	assert_eq(thumb.texture.resource_path, "res://assets/sprites/armor_rare.png")

func test_empty_weapon_slot_has_no_thumbnail_texture():
	var inv := ItemInventory.new()
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var thumb := panel.find_child("SlotThumb_%d" % ItemData.Slot.WEAPON, true, false) as TextureRect
	assert_null(thumb, "empty weapon slot must not include a thumbnail node")

# An equipped armor/accessory has no thumbnail art yet, so it must still be
# visually distinguishable from an empty slot: the tile carries an "equipped"
# flag and a distinct (rarity-coloured) border versus an empty slot.
func test_equipped_artless_slot_is_distinct_from_empty():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("chain_mail"))  # armor, RARE, no thumbnail
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var filled := panel.find_child("SlotTile_%d" % ItemData.Slot.ARMOR, true, false) as Button
	var empty := panel.find_child("SlotTile_%d" % ItemData.Slot.ACCESSORY, true, false) as Button
	assert_not_null(filled, "armor tile must exist")
	assert_not_null(empty, "accessory tile must exist")
	assert_true(filled.get_meta("equipped", false), "equipped armor tile must be flagged equipped")
	assert_false(empty.get_meta("equipped", false), "empty accessory tile must not be flagged equipped")
	var filled_sb := filled.get_theme_stylebox("normal") as StyleBoxFlat
	var empty_sb := empty.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(filled_sb, "filled tile must have a StyleBoxFlat normal style")
	assert_not_null(empty_sb, "empty tile must have a StyleBoxFlat normal style")
	assert_ne(filled_sb.border_color, empty_sb.border_color,
		"filled and empty tiles must have distinct border colours")

func test_null_inventory_does_not_crash():
	var panel := _make_panel()
	panel.refresh(null, _make_char())
	assert_not_null(panel.find_child("Section_Equipped", true, false),
		"sections must still render with a null inventory")

# Regression: the bag must NOT have its own ScrollContainer. The whole
# Character submenu scrolls as one page (via the outer TabScroll), so the
# bag lays out at full height — the previous nested scroll trapped the item
# list in a cramped ~24px window that made bag items hard to see.
func test_bag_has_no_inner_scroll_container():
	var inv := ItemInventory.new()
	for i in range(8):
		inv.add_to_bag(ItemCatalog.find("iron_sword"))
	var panel := _make_panel()
	panel.refresh(inv, _make_char())
	var scrolls := panel.find_children("*", "ScrollContainer", true, false)
	assert_eq(scrolls.size(), 0,
		"equipment panel must contain no ScrollContainer — the whole page scrolls instead")
