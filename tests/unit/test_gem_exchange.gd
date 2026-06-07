extends GutTest

# Gem → Gold exchange (convert diamonds to money). Mirrors the gem-bundle
# dispatch but in reverse: exchange rows are priced in Gems (debited by
# ShopScreen's soft-currency path) and grant Gold via PurchaseGrantHandler.
# Rate is 1 Gem = 100 Gold across three tiered rows.

func test_exchange_product_grant_type():
	assert_eq(
		PurchaseRegistry.grant_type_for(PurchaseRegistry.EXCHANGE_SMALL_POUCH),
		PurchaseRegistry.GRANT_GEM_EXCHANGE)

func test_grant_handler_credits_gold():
	var ledger := CurrencyLedger.new()
	var ok := PurchaseGrantHandler.handle(
		PurchaseRegistry.EXCHANGE_SMALL_POUCH, null, null, null, ledger)
	assert_true(ok, "exchange grant returns true")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 1000,
		"small pouch grants 1000 Gold")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0,
		"grant handler does not touch Gems (debit is ShopScreen's job)")

func test_catalog_has_three_exchange_rows_priced_in_gems():
	var count := 0
	for item in ShopCatalog.items():
		if item.category != ShopCatalogItem.CATEGORY_EXCHANGE:
			continue
		count += 1
		assert_eq(item.currency_type, CurrencyLedger.Currency.GEM,
			"exchange row %s must price in Gems" % item.product_id)
		assert_true(item.price > 0, "exchange row %s needs a Gem price" % item.product_id)
	assert_eq(count, 3, "expected three exchange rows")

# --- End-to-end ShopScreen flow: debit Gems, credit Gold --------------------

const SHOP_SCREEN_SCENE := "res://scenes/shop_screen.tscn"

func _make_screen(ledger: CurrencyLedger) -> ShopScreen:
	var screen: ShopScreen = load(SHOP_SCREEN_SCENE).instantiate()
	add_child_autofree(screen)
	screen.setup(ledger, SkillInventory.new(), PaidUnlockInventory.new(), null)
	return screen

func test_buy_exchange_debits_gems_and_credits_gold():
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GEM)
	var screen := _make_screen(ledger)
	screen._on_buy_pressed(PurchaseRegistry.EXCHANGE_SMALL_POUCH)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 90,
		"10 Gems debited")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 1000,
		"1000 Gold credited")

func test_buy_exchange_with_insufficient_gems_is_noop():
	var ledger := CurrencyLedger.new()
	ledger.credit(5, CurrencyLedger.Currency.GEM)
	var screen := _make_screen(ledger)
	screen._on_buy_pressed(PurchaseRegistry.EXCHANGE_SMALL_POUCH)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 5,
		"Gems untouched when unaffordable")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0,
		"no Gold minted on failed exchange")

func test_exchange_row_never_owned():
	# Exchange is a repeatable consumable — re-buyable, never shows "Owned".
	var ledger := CurrencyLedger.new()
	ledger.credit(1000, CurrencyLedger.Currency.GEM)
	var screen := _make_screen(ledger)
	var item := ShopCatalog.find(PurchaseRegistry.EXCHANGE_SMALL_POUCH)
	assert_false(screen._is_owned(item), "exchange row must never be Owned")
