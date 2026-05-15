extends GutTest

# ShopCatalog (PRD #53 / issue #64). Catalog drives the ShopScreen item list
# without coupling to the scene; tests here pin the contract every row must
# satisfy so a future row addition can't silently land malformed.

const VALID_CATEGORIES := ["class_upgrade", "class_unlock", "skill", "gem_bundle"]

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

func test_at_least_one_skill_row_exists():
	var any_skill := false
	for item in ShopCatalog.items():
		if item.category == ShopCatalogItem.CATEGORY_SKILL:
			any_skill = true
			break
	assert_true(any_skill, "expected at least one skill row in catalog")

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
