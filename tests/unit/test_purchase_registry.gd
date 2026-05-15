extends GutTest

# --- Issue tests (acceptance criteria) ---

func test_class_upgrade_grant_type():
	assert_eq(
		PurchaseRegistry.grant_type_for(PurchaseRegistry.UPGRADE_WIZARD_KITTEN_WIZARD_CAT),
		PurchaseRegistry.GRANT_CLASS_UPGRADE)

func test_all_products_have_grant_type():
	for id in PurchaseRegistry.ALL_PRODUCT_IDS:
		assert_ne(PurchaseRegistry.grant_type_for(id), "",
			"product %s missing grant type" % id)

func test_unknown_product_returns_empty():
	assert_eq(PurchaseRegistry.grant_type_for("fake_product_xyz"), "")

func test_class_for_product_mage_upgrade():
	var result := PurchaseRegistry.class_for_product(PurchaseRegistry.UPGRADE_WIZARD_KITTEN_WIZARD_CAT)
	assert_eq(result, int(CharacterData.CharacterClass.WIZARD_KITTEN))

func test_class_for_product_cosmetic_returns_minus_one():
	assert_eq(PurchaseRegistry.class_for_product(PurchaseRegistry.COSMETIC_COAT_PACK), -1)

# --- Coverage extras ---

func test_class_upgrade_thief_and_ninja_map_to_source_class():
	# class_for_product returns the *source* class (the one being upgraded);
	# the target lives in ClassTierUpgrade.TIER_MAP. All three Tier-1 products
	# now route end-to-end (Master Thief / Shadow Ninja landed alongside
	# Archmage in CharacterData.CharacterClass + TIER_MAP).
	assert_eq(
		PurchaseRegistry.class_for_product(PurchaseRegistry.UPGRADE_BATTLE_KITTEN_BATTLE_CAT),
		int(CharacterData.CharacterClass.BATTLE_KITTEN))
	assert_eq(
		PurchaseRegistry.class_for_product(PurchaseRegistry.UPGRADE_SLEEPY_KITTEN_SLEEPY_CAT),
		int(CharacterData.CharacterClass.SLEEPY_KITTEN))

func test_cosmetic_grant_type():
	for id in [
		PurchaseRegistry.COSMETIC_COAT_PACK,
		PurchaseRegistry.COSMETIC_SPELL_EFFECTS,
		PurchaseRegistry.COSMETIC_DUNGEON_SKINS,
	]:
		assert_eq(PurchaseRegistry.grant_type_for(id),
			PurchaseRegistry.GRANT_COSMETIC_PACK,
			"%s should be a cosmetic_pack grant" % id)

func test_class_unlock_grant_type():
	assert_eq(
		PurchaseRegistry.grant_type_for(PurchaseRegistry.CLASS_UNLOCK_CHONK_KITTEN),
		PurchaseRegistry.GRANT_CLASS_UNLOCK)

func test_class_for_product_class_unlock_returns_minus_one():
	# class-unlock products carry no CharacterClass — slice 6 routes them via
	# UnlockRegistry/class id, not by class int.
	assert_eq(
		PurchaseRegistry.class_for_product(PurchaseRegistry.CLASS_UNLOCK_CHONK_KITTEN),
		-1)

func test_class_for_product_unknown_returns_minus_one():
	assert_eq(PurchaseRegistry.class_for_product("totally_unknown"), -1)

func test_all_product_ids_unique():
	# Catch accidental duplicates in the catalog before they ship to Play Console.
	var seen := {}
	for id in PurchaseRegistry.ALL_PRODUCT_IDS:
		assert_false(seen.has(id), "duplicate product id in ALL_PRODUCT_IDS: %s" % id)
		seen[id] = true

func test_all_product_ids_includes_every_category():
	# Sanity: ALL_PRODUCT_IDS contains at least one product of each grant type
	# so BillingManager's startup query covers the whole catalog.
	var types_seen := {}
	for id in PurchaseRegistry.ALL_PRODUCT_IDS:
		types_seen[PurchaseRegistry.grant_type_for(id)] = true
	assert_true(types_seen.has(PurchaseRegistry.GRANT_CLASS_UPGRADE))
	assert_true(types_seen.has(PurchaseRegistry.GRANT_COSMETIC_PACK))
	assert_true(types_seen.has(PurchaseRegistry.GRANT_CLASS_UNLOCK))
