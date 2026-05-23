extends GutTest

func test_all_items_returns_eighty_four():
	# 72 DROP items + 12 SHOP items added in Slice 6 of PRD #201.
	assert_eq(ItemCatalog.all_items().size(), 84)

func test_iron_sword_content():
	var item := ItemCatalog.find("iron_sword")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.WEAPON)
	assert_eq(item.rarity, ItemData.Rarity.COMMON)
	assert_eq(item.bonuses.size(), 1)
	assert_eq(item.bonuses[0].stat_name, "attack")
	assert_eq(item.bonuses[0].stat_bonus, 2.0)

func test_items_for_slot_armor():
	# 24 DROP armor + 4 SHOP armor (one per class) from Slice 6.
	var armor := ItemCatalog.items_for_slot(ItemData.Slot.ARMOR)
	assert_eq(armor.size(), 28)
	for item in armor:
		assert_eq(item.slot, ItemData.Slot.ARMOR)

func test_items_for_rarity_epic():
	# 24 DROP epics + 4 SHOP epics (one per class) from Slice 6.
	var epics := ItemCatalog.items_for_rarity(ItemData.Rarity.EPIC)
	assert_eq(epics.size(), 28)
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

func test_all_items_have_bonuses():
	for item in ItemCatalog.all_items():
		assert_true(item.bonuses.size() > 0, "item %s has empty bonuses" % item.id)

func test_shop_items_are_class_tagged_and_source_shop():
	# Slice 6 of PRD #201: every "shop_*" id must be source == SHOP and
	# carry an allowed_classes tag so ShopCatalog can filter by class.
	var count := 0
	for item in ItemCatalog.all_items():
		if not item.id.begins_with("shop_"):
			continue
		count += 1
		assert_eq(item.source, ItemData.Source.SHOP,
			"item %s should be source SHOP" % item.id)
		assert_true(item.allowed_classes.size() > 0,
			"shop item %s missing allowed_classes" % item.id)
	assert_eq(count, 12, "expected 12 shop_* items in catalog")

func test_drop_items_remain_drop():
	# Sanity guard: nothing flipped a pre-Slice-6 item's source on us.
	for item in ItemCatalog.all_items():
		if item.id.begins_with("shop_"):
			continue
		assert_eq(item.source, ItemData.Source.DROP,
			"non-shop item %s should be source DROP" % item.id)

func test_every_class_covers_full_slot_rarity_matrix():
	var classes := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	var slots := [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.ACCESSORY]
	var rarities := [ItemData.Rarity.COMMON, ItemData.Rarity.RARE, ItemData.Rarity.EPIC]
	var items := ItemCatalog.all_items()
	for klass in classes:
		for slot in slots:
			for rarity in rarities:
				var found := false
				for item in items:
					if item.slot == slot and item.rarity == rarity and ClassEligibility.is_class_allowed(item, klass):
						found = true
						break
				assert_true(found, "class %d missing slot=%d rarity=%d" % [klass, slot, rarity])

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
