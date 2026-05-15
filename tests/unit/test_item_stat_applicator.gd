extends GutTest

func _base_char() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Test")

func test_apply_adds_int_stat_bonus():
	var inv := ItemInventory.new()
	var c := _base_char()
	var base_attack := c.attack
	inv.equip(ItemCatalog.find("iron_sword"))
	ItemStatApplicator.apply(inv, c)
	assert_eq(c.attack, base_attack + 2)

func test_apply_adds_float_stat_bonus():
	var inv := ItemInventory.new()
	var c := _base_char()
	var base_evasion := c.evasion
	inv.equip(ItemCatalog.find("shadow_amulet"))
	ItemStatApplicator.apply(inv, c)
	assert_almost_eq(c.evasion, base_evasion + 0.08, 0.001)

func test_recompute_returns_to_base_after_unequip():
	var inv := ItemInventory.new()
	var c := _base_char()
	var base := _base_char()
	inv.equip(ItemCatalog.find("iron_sword"))
	ItemStatApplicator.apply(inv, c)
	inv.unequip(ItemData.Slot.WEAPON)
	ItemStatApplicator.recompute(inv, c, base)
	assert_eq(c.attack, base.attack)

func test_apply_multi_slot_simultaneously():
	var inv := ItemInventory.new()
	var c := _base_char()
	var base_attack := c.attack
	var base_defense := c.defense
	var base_luck := c.luck
	inv.equip(ItemCatalog.find("iron_sword"))
	inv.equip(ItemCatalog.find("leather_vest"))
	inv.equip(ItemCatalog.find("lucky_charm"))
	ItemStatApplicator.apply(inv, c)
	assert_eq(c.attack, base_attack + 2)
	assert_eq(c.defense, base_defense + 2)
	assert_eq(c.luck, base_luck + 3)

func test_apply_empty_inventory_no_change():
	var inv := ItemInventory.new()
	var c := _base_char()
	var base := _base_char()
	ItemStatApplicator.apply(inv, c)
	assert_eq(c.attack, base.attack)
	assert_eq(c.defense, base.defense)
	assert_eq(c.max_hp, base.max_hp)
	assert_almost_eq(c.evasion, base.evasion, 0.001)
	assert_almost_eq(c.speed, base.speed, 0.001)

func test_apply_null_inventory_no_crash():
	var c := _base_char()
	var base_attack := c.attack
	ItemStatApplicator.apply(null, c)
	assert_eq(c.attack, base_attack)
