extends GutTest

# --- Issue tests (acceptance criteria) ---

func test_class_upgrade_grant_type():
	assert_eq(
		PurchaseRegistry.grant_type_for(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE),
		PurchaseRegistry.GRANT_CLASS_UPGRADE)

func test_all_products_have_grant_type():
	for id in PurchaseRegistry.ALL_PRODUCT_IDS:
		assert_ne(PurchaseRegistry.grant_type_for(id), "",
			"product %s missing grant type" % id)

func test_unknown_product_returns_empty():
	assert_eq(PurchaseRegistry.grant_type_for("fake_product_xyz"), "")

func test_class_for_product_mage_upgrade():
	var result := PurchaseRegistry.class_for_product(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE)
	assert_eq(result, int(CharacterData.CharacterClass.MAGE))

func test_class_for_product_cosmetic_returns_minus_one():
	assert_eq(PurchaseRegistry.class_for_product(PurchaseRegistry.COSMETIC_COAT_PACK), -1)

# --- Coverage extras ---

func test_class_upgrade_thief_and_ninja_map_to_source_class():
	# Master Thief / Shadow Ninja aren't in CharacterClass yet, but the product
	# IDs are pre-wired so Play Console can list them. class_for_product still
	# returns the *source* class — slice 6 dispatches via ClassTierUpgrade.
	assert_eq(
		PurchaseRegistry.class_for_product(PurchaseRegistry.UPGRADE_THIEF_MASTER_THIEF),
		int(CharacterData.CharacterClass.THIEF))
	assert_eq(
		PurchaseRegistry.class_for_product(PurchaseRegistry.UPGRADE_NINJA_SHADOW_NINJA),
		int(CharacterData.CharacterClass.NINJA))

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
		PurchaseRegistry.grant_type_for(PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE),
		PurchaseRegistry.GRANT_CLASS_UNLOCK)

func test_class_for_product_class_unlock_returns_minus_one():
	# class-unlock products carry no CharacterClass — slice 6 routes them via
	# UnlockRegistry/class id, not by class int.
	assert_eq(
		PurchaseRegistry.class_for_product(PurchaseRegistry.CLASS_UNLOCK_ARCHMAGE),
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
