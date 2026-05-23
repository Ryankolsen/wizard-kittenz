extends GutTest

func test_all_items_returns_thirty_six():
	assert_eq(ItemCatalog.all_items().size(), 36)

func test_iron_sword_content():
	var item := ItemCatalog.find("iron_sword")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.WEAPON)
	assert_eq(item.rarity, ItemData.Rarity.COMMON)
	assert_eq(item.bonuses.size(), 1)
	assert_eq(item.bonuses[0].stat_name, "attack")
	assert_eq(item.bonuses[0].stat_bonus, 2.0)

func test_items_for_slot_armor():
	var armor := ItemCatalog.items_for_slot(ItemData.Slot.ARMOR)
	assert_eq(armor.size(), 12)
	for item in armor:
		assert_eq(item.slot, ItemData.Slot.ARMOR)

func test_items_for_rarity_epic():
	var epics := ItemCatalog.items_for_rarity(ItemData.Rarity.EPIC)
	assert_eq(epics.size(), 12)
	for item in epics:
		assert_eq(item.rarity, ItemData.Rarity.EPIC)

func test_find_unknown_returns_null():
	assert_null(ItemCatalog.find("nonexistent"))

func test_all_ids_unique():
	var ids := {}
	for item in ItemCatalog.all_items():
		assert_false(ids.has(item.id), "duplicate id %s" % item.id)
		ids[item.id] = true

func test_all_items_have_allowed_classes():
	for item in ItemCatalog.all_items():
		assert_true(item.allowed_classes.size() > 0, "item %s has empty allowed_classes" % item.id)

func test_lucky_charm_is_generic():
	var item := ItemCatalog.find("lucky_charm")
	assert_not_null(item)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "lucky_charm missing class %d" % klass)

func test_enchanted_blade_is_dual_stat():
	var item := ItemCatalog.find("enchanted_blade")
	assert_not_null(item)
	assert_eq(item.bonuses.size(), 2)
	var stats := {}
	for b in item.bonuses:
		stats[b.stat_name] = b.stat_bonus
	assert_true(stats.has("attack"), "Enchanted Blade carries attack bonus")
	assert_true(stats.has("magic_attack"), "Enchanted Blade carries magic_attack bonus")
	assert_eq(stats["attack"], 4.0)
	assert_eq(stats["magic_attack"], 4.0)
