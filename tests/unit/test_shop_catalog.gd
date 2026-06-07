extends GutTest

# ShopCatalog (PRD #53 / issue #64). Catalog drives the ShopScreen item list
# without coupling to the scene; tests here pin the contract every row must
# satisfy so a future row addition can't silently land malformed.

const VALID_CATEGORIES := ["class_upgrade", "class_unlock", "skill", "gem_bundle", "gear", "exchange", "potion"]

func test_items_returns_non_empty_array():
	var items := ShopCatalog.items()
	assert_not_null(items)
	assert_true(items.size() > 0)

func test_every_item_has_required_fields():
	for item in ShopCatalog.items():
		assert_true(item.product_id != "", "product_id empty: " + item.display_name)
		assert_true(item.display_name != "", "display_name empty: " + item.product_id)
		assert_true(item.price > 0, "price not positive: " + item.product_id)
		assert_true(item.currency_type >= 0, "currency_type negative: " + item.product_id)
		assert_true(item.category in VALID_CATEGORIES,
			"unknown category '%s' on %s" % [item.category, item.product_id])

func test_no_duplicate_product_ids():
	var seen := {}
	for item in ShopCatalog.items():
		assert_false(item.product_id in seen, "duplicate product_id: " + item.product_id)
		seen[item.product_id] = true

func test_covers_four_class_upgrades():
	var count := 0
	for item in ShopCatalog.items():
		if item.category == ShopCatalogItem.CATEGORY_CLASS_UPGRADE:
			count += 1
	assert_eq(count, 4)

func test_covers_one_class_unlock():
	var count := 0
	for item in ShopCatalog.items():
		if item.category == ShopCatalogItem.CATEGORY_CLASS_UNLOCK:
			count += 1
	assert_eq(count, 1)

func test_covers_four_gem_bundles_with_prd_price_tiers():
	var prices := []
	for item in ShopCatalog.items():
		if item.category == ShopCatalogItem.CATEGORY_GEM_BUNDLE:
			prices.append(item.price)
	prices.sort()
	assert_eq(prices, [99, 499, 999, 1999])

func test_gem_bundles_are_only_real_money_priced_rows():
	# Non-bundle rows price in soft/premium currency; bundles encode cents.
	for item in ShopCatalog.items():
		if item.category == ShopCatalogItem.CATEGORY_GEM_BUNDLE:
			continue
		assert_true(item.currency_type == CurrencyLedger.Currency.GOLD
				or item.currency_type == CurrencyLedger.Currency.GEM,
			"non-bundle row has unexpected currency: " + item.product_id)

# --- Slice 6 of PRD #201: Gear category --------------------------------------

func test_no_args_omits_gear_category():
	# Pre-Slice-6 callers (no character context) still see the legacy row set.
	for item in ShopCatalog.items():
		assert_ne(item.category, ShopCatalogItem.CATEGORY_GEAR,
			"gear row leaked with no class context: " + item.product_id)

func test_wizard_sees_at_least_one_gear_row():
	var rows := ShopCatalog.items(CharacterData.CharacterClass.WIZARD_KITTEN)
	var saw := false
	for item in rows:
		if item.category == ShopCatalogItem.CATEGORY_GEAR:
			saw = true
			# Every gear row must be wizard-eligible at the ItemCatalog level.
			var data := ItemCatalog.find(item.product_id)
			assert_not_null(data, "product_id %s not in ItemCatalog" % item.product_id)
			assert_true(ClassEligibility.is_class_allowed(data,
					CharacterData.CharacterClass.WIZARD_KITTEN),
				"gear row %s not allowed for wizard" % item.product_id)
			assert_eq(data.source, ItemData.Source.SHOP,
				"gear row %s not source SHOP" % item.product_id)
	assert_true(saw, "expected at least one CATEGORY_GEAR row for wizard")

func test_gear_prices_match_rarity_tiers():
	# 50 / 250 / 1000 Gold for Common / Rare / Epic — AC4.
	var rows := ShopCatalog.items(CharacterData.CharacterClass.WIZARD_KITTEN)
	var saw := {"common": false, "rare": false, "epic": false}
	for item in rows:
		if item.category != ShopCatalogItem.CATEGORY_GEAR:
			continue
		assert_eq(item.currency_type, CurrencyLedger.Currency.GOLD,
			"gear row %s must price in Gold" % item.product_id)
		var data := ItemCatalog.find(item.product_id)
		match data.rarity:
			ItemData.Rarity.COMMON:
				assert_eq(item.price, 50)
				saw["common"] = true
			ItemData.Rarity.RARE:
				assert_eq(item.price, 250)
				saw["rare"] = true
			ItemData.Rarity.EPIC:
				assert_eq(item.price, 1000)
				saw["epic"] = true
	for k in saw:
		assert_true(saw[k], "no gear row at rarity " + k)

func test_wizard_never_sees_chonk_gear():
	# Class isolation — Wizard must never see Chonk's Heavy Club (or any
	# CHONK-tagged gear row).
	var rows := ShopCatalog.items(CharacterData.CharacterClass.WIZARD_KITTEN)
	for item in rows:
		if item.category != ShopCatalogItem.CATEGORY_GEAR:
			continue
		var data := ItemCatalog.find(item.product_id)
		assert_false(ClassEligibility.is_class_allowed(data,
				CharacterData.CharacterClass.CHONK_KITTEN)
				and not ClassEligibility.is_class_allowed(data,
				CharacterData.CharacterClass.WIZARD_KITTEN),
			"wizard saw chonk-only gear: " + item.product_id)

func test_cat_tier_inherits_kitten_gear():
	# BATTLE_CAT must see Kitten-tagged shop gear via ClassEligibility inheritance.
	var kitten_rows := ShopCatalog.items(CharacterData.CharacterClass.BATTLE_KITTEN)
	var cat_rows := ShopCatalog.items(CharacterData.CharacterClass.BATTLE_CAT)
	var kitten_gear := []
	for r in kitten_rows:
		if r.category == ShopCatalogItem.CATEGORY_GEAR:
			kitten_gear.append(r.product_id)
	var cat_gear := []
	for r in cat_rows:
		if r.category == ShopCatalogItem.CATEGORY_GEAR:
			cat_gear.append(r.product_id)
	assert_eq(cat_gear, kitten_gear,
		"battle cat should see the same gear rows as battle kitten")
	assert_true(cat_gear.size() > 0)

func test_find_resolves_gear_product_id_without_class_context():
	# Refresh paths (post-purchase row update) hit find() without a character.
	var row := ShopCatalog.find("shop_archmage_staff")
	assert_not_null(row)
	assert_eq(row.category, ShopCatalogItem.CATEGORY_GEAR)
	assert_eq(row.price, 1000)
	assert_eq(row.currency_type, CurrencyLedger.Currency.GOLD)

# --- Slice 3 of PRD #292: shop gear rows use the formatter ------------------

func test_gear_row_rarity_field_populated_from_item_data():
	# shop_archmage_staff is Epic in ItemCatalog (line 113), so the row's
	# rarity field must mirror that — Slice 2 (#294) tints the equipped tile
	# from this same source, Slice 3 surfaces it to the shop row.
	var row := ShopCatalog.find("shop_archmage_staff")
	assert_not_null(row)
	assert_eq(row.rarity, ItemData.Rarity.EPIC)

func test_gear_row_bonus_lines_humanized_via_formatter():
	# Acceptance: "+N Magic Attack" — humanized, not "magic_attack +N.0".
	var row := ShopCatalog.find("shop_archmage_staff")
	assert_not_null(row)
	assert_eq(row.bonus_lines.size(), 1)
	assert_eq(row.bonus_lines[0], "+10 Magic Attack")

func test_gem_bundle_row_unchanged_by_formatter_path():
	# Regression guard: non-gear rows keep their free-form description and an
	# unset/default rarity sentinel. The formatter must be gear-only.
	var row := ShopCatalog.find(PurchaseRegistry.GEM_BUNDLE_STARTER)
	assert_not_null(row)
	assert_eq(row.rarity, -1)
	assert_eq(row.bonus_lines.size(), 0)
	assert_true(row.description.find("Gems") >= 0,
		"gem bundle description should still describe gems: " + row.description)

func test_gear_row_description_no_longer_uses_run_on_format():
	# The old "magic_attack +10.0" string must not appear anywhere on the gear
	# row — AC: "old attack +2.0 style description no longer appears for gear".
	var row := ShopCatalog.find("shop_archmage_staff")
	assert_not_null(row)
	assert_eq(row.description.find("magic_attack"), -1,
		"gear row leaked raw stat key: " + row.description)
	assert_eq(row.description.find("+10.0"), -1,
		"gear row leaked unhumanized number format: " + row.description)
