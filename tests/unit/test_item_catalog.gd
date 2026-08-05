extends GutTest

func test_all_items_returns_ninety():
	# 72 DROP items + 12 SHOP items added in Slice 6 of PRD #201 + Guardian's
	# Locket (issue #459) + Executioner's Signet (issue #462) + Bramble Plate
	# (issue #463) + Chest Goblin Gloves (issue #464) + Fat Cat Coin Purse
	# (issue #465) + Nine Lives Collar (issue #466) + Alchemist's Flask
	# (issue #467).
	assert_eq(ItemCatalog.all_items().size(), 91)

func test_iron_sword_content():
	var item := ItemCatalog.find("iron_sword")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.WEAPON)
	assert_eq(item.rarity, ItemData.Rarity.COMMON)
	assert_eq(item.bonuses.size(), 1)
	assert_eq(item.bonuses[0].stat_name, "attack")
	assert_eq(item.bonuses[0].stat_bonus, 2.0)

func test_battle_weapon_new_names():
	# Slice 1 of PRD #273: Battle's 7 weapons get themed display names while
	# ids/stats stay unchanged (test_iron_sword_content covers stat invariance).
	assert_eq(ItemCatalog.find("iron_sword").display_name, "Slippery Mackerel")
	assert_eq(ItemCatalog.find("rusted_dagger").display_name, "Pointy Stick")
	assert_eq(ItemCatalog.find("shop_iron_dirk").display_name, "Butter Knife")
	assert_eq(ItemCatalog.find("silver_sword").display_name, "Alley-Cat Cutlass")
	assert_eq(ItemCatalog.find("knights_sabre").display_name, "Tin-Knight Sabre")
	assert_eq(ItemCatalog.find("enchanted_blade").display_name, "Clawbur")
	assert_eq(ItemCatalog.find("dragonslayer_greatsword").display_name, "Catana")

func test_wizard_weapon_new_names():
	# Slice 2 of PRD #273: Wizard's 7 weapons get themed display names while
	# ids/stats stay unchanged.
	assert_eq(ItemCatalog.find("apprentice_wand").display_name, "Birthday Sparkler")
	assert_eq(ItemCatalog.find("novice_wand").display_name, "Firefly Jar")
	assert_eq(ItemCatalog.find("arcane_staff").display_name, "Crackle Wand")
	assert_eq(ItemCatalog.find("runed_staff").display_name, "Stormtwig Staff")
	assert_eq(ItemCatalog.find("starfire_rod").display_name, "Comet Caller")
	assert_eq(ItemCatalog.find("voidcaller_staff").display_name, "Wand of the Big Bang")
	assert_eq(ItemCatalog.find("shop_archmage_staff").display_name, "Archmage's Astrolabe")
	# Stat invariance: rename is display-only — apprentice_wand still grants
	# magic_attack +3.0.
	var aw := ItemCatalog.find("apprentice_wand")
	assert_eq(aw.bonuses.size(), 1)
	assert_eq(aw.bonuses[0].stat_name, "magic_attack")
	assert_eq(aw.bonuses[0].stat_bonus, 3.0)

func test_items_for_slot_armor():
	# 24 DROP armor + 4 SHOP armor (one per class) from Slice 6 + Bramble
	# Plate (issue #463).
	var armor := ItemCatalog.items_for_slot(ItemData.Slot.ARMOR)
	assert_eq(armor.size(), 29)
	for item in armor:
		assert_eq(item.slot, ItemData.Slot.ARMOR)

func test_items_for_rarity_epic():
	# 24 DROP epics + 4 SHOP epics (one per class) from Slice 6 + Guardian's
	# Locket (issue #459) + Executioner's Signet (issue #462) + Bramble Plate
	# (issue #463) + Chest Goblin Gloves (issue #464) + Fat Cat Coin Purse
	# (issue #465) + Nine Lives Collar (issue #466) + Alchemist's Flask
	# (issue #467).
	var epics := ItemCatalog.items_for_rarity(ItemData.Rarity.EPIC)
	assert_eq(epics.size(), 35)
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

func test_guardians_locket_is_generic_and_class_neutral():
	# Issue #459: Guardian's Locket carries the Lifesteal passive and must
	# be usable by every class, with a stat bonus that isn't caster-biased
	# (no magic_attack-style stat), same convention audited for lucky_charm.
	var item := ItemCatalog.find("guardians_locket")
	assert_not_null(item)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "guardians_locket missing class %d" % klass)
	for b in item.bonuses:
		assert_ne(b.stat_name, "magic_attack", "guardians_locket must not use a caster-only stat")
	assert_eq(ItemPassiveEffectResolver.passive_id_for(item.id), ItemPassiveEffectResolver.PASSIVE_LIFESTEAL)

func test_executioners_signet_is_generic_and_class_neutral():
	# Issue #462: Executioner's Signet carries the Crit Echo passive and must
	# be usable by every class, with a stat bonus that isn't caster-biased,
	# same convention as Guardian's Locket above.
	var item := ItemCatalog.find("executioners_signet")
	assert_not_null(item)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "executioners_signet missing class %d" % klass)
	for b in item.bonuses:
		assert_ne(b.stat_name, "magic_attack", "executioners_signet must not use a caster-only stat")
	assert_eq(ItemPassiveEffectResolver.passive_id_for(item.id), ItemPassiveEffectResolver.PASSIVE_CRIT_ECHO)

func test_bramble_plate_is_generic_and_class_neutral():
	# Issue #463: Bramble Plate carries the Thorns passive and must be usable
	# by every class, with a stat bonus that isn't caster-biased, same
	# convention as Guardian's Locket/Executioner's Signet above.
	var item := ItemCatalog.find("bramble_plate")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.ARMOR)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "bramble_plate missing class %d" % klass)
	for b in item.bonuses:
		assert_ne(b.stat_name, "magic_attack", "bramble_plate must not use a caster-only stat")
	assert_eq(ItemPassiveEffectResolver.passive_id_for(item.id), ItemPassiveEffectResolver.PASSIVE_THORNS)

func test_chest_goblin_gloves_is_generic_and_class_neutral():
	# Issue #464: Chest Goblin Gloves is a plain luck-stat item (no passive
	# effect) and must be usable by every class, same class-unrestricted
	# convention as Guardian's Locket/Executioner's Signet/Bramble Plate above.
	var item := ItemCatalog.find("chest_goblin_gloves")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.ACCESSORY)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "chest_goblin_gloves missing class %d" % klass)
	assert_eq(item.bonuses.size(), 1)
	assert_eq(item.bonuses[0].stat_name, "luck")
	for b in item.bonuses:
		assert_ne(b.stat_name, "magic_attack", "chest_goblin_gloves must not use a caster-only stat")
	assert_eq(ItemPassiveEffectResolver.passive_id_for(item.id), "", "chest_goblin_gloves has no passive effect")

func test_fat_cat_coin_purse_is_generic_and_class_neutral():
	# Issue #465: Fat Cat Coin Purse is a plain luck-stat item (no passive
	# effect) and must be usable by every class, same class-unrestricted
	# convention as Chest Goblin Gloves above.
	var item := ItemCatalog.find("fat_cat_coin_purse")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.ACCESSORY)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "fat_cat_coin_purse missing class %d" % klass)
	assert_eq(item.bonuses.size(), 1)
	assert_eq(item.bonuses[0].stat_name, "luck")
	for b in item.bonuses:
		assert_ne(b.stat_name, "magic_attack", "fat_cat_coin_purse must not use a caster-only stat")
	assert_eq(ItemPassiveEffectResolver.passive_id_for(item.id), "", "fat_cat_coin_purse has no passive effect")

func test_nine_lives_collar_is_generic_and_class_neutral():
	# Issue #466: Nine Lives Collar carries the Second Wind passive and must
	# be usable by every class, with a stat bonus that isn't caster-biased,
	# same convention as Guardian's Locket/Executioner's Signet/Bramble Plate
	# above.
	var item := ItemCatalog.find("nine_lives_collar")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.ACCESSORY)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "nine_lives_collar missing class %d" % klass)
	for b in item.bonuses:
		assert_ne(b.stat_name, "magic_attack", "nine_lives_collar must not use a caster-only stat")
	assert_eq(ItemPassiveEffectResolver.passive_id_for(item.id), ItemPassiveEffectResolver.PASSIVE_SECOND_WIND)

func test_alchemists_flask_is_generic_and_class_neutral():
	# Issue #467: Alchemist's Flask is a plain regeneration-stat item (no
	# passive effect) and must be usable by every class, same class-
	# unrestricted convention as Chest Goblin Gloves/Fat Cat Coin Purse above.
	var item := ItemCatalog.find("alchemists_flask")
	assert_not_null(item)
	assert_eq(item.slot, ItemData.Slot.ACCESSORY)
	var expected := [
		CharacterData.CharacterClass.BATTLE_KITTEN,
		CharacterData.CharacterClass.WIZARD_KITTEN,
		CharacterData.CharacterClass.SLEEPY_KITTEN,
		CharacterData.CharacterClass.CHONK_KITTEN,
	]
	for klass in expected:
		assert_true(item.allowed_classes.has(klass), "alchemists_flask missing class %d" % klass)
	assert_eq(item.bonuses.size(), 1)
	assert_eq(item.bonuses[0].stat_name, "regeneration")
	for b in item.bonuses:
		assert_ne(b.stat_name, "magic_attack", "alchemists_flask must not use a caster-only stat")
	assert_eq(ItemPassiveEffectResolver.passive_id_for(item.id), "", "alchemists_flask has no passive effect")
