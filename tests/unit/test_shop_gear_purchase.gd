extends GutTest

# Slice 6 of PRD #201: shop gear purchase wiring. The PurchaseGrantHandler
# resolves a shop product_id back to ItemCatalog (source == SHOP) and adds
# the ItemData to the player's bag; insufficient-gold paths leave both the
# ledger and the bag untouched.

const SHOP_SCREEN_SCENE := "res://scenes/shop_screen.tscn"

class FakeBilling:
	extends Node

	signal purchase_succeeded(product_id: String)
	signal purchase_failed(product_id: String)

	func start_purchase(_pid: String) -> void:
		pass

func _wizard(level: int = 11) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "w")
	c.level = level
	return c

# --- Grant-handler dispatch -------------------------------------------------

func test_grant_handler_adds_shop_gear_to_bag():
	var inv := ItemInventory.new()
	var ok := PurchaseGrantHandler.handle("shop_archmage_staff",
		null, null, null, null, null, inv)
	assert_true(ok, "shop gear grant should return true")
	assert_eq(inv.bag_items().size(), 1)
	assert_eq(inv.bag_items()[0].id, "shop_archmage_staff")

func test_grant_handler_rejects_drop_only_id():
	# iron_sword exists in the catalog but is source == DROP; the grant route
	# must not surface it through the shop path.
	var inv := ItemInventory.new()
	var ok := PurchaseGrantHandler.handle("iron_sword",
		null, null, null, null, null, inv)
	assert_false(ok)
	assert_eq(inv.bag_items().size(), 0)

func test_grant_handler_noop_without_item_inventory():
	var ok := PurchaseGrantHandler.handle("shop_archmage_staff",
		null, null, null, null, null, null)
	assert_false(ok)

func test_purchase_registry_routes_shop_id_to_grant_item():
	assert_eq(PurchaseRegistry.grant_type_for("shop_archmage_staff"),
		PurchaseRegistry.GRANT_ITEM)
	assert_eq(PurchaseRegistry.grant_type_for("iron_sword"), "",
		"DROP catalog ids must not be purchasable")

# --- Shop screen wiring -----------------------------------------------------

func _make_screen(ledger: CurrencyLedger, inv: ItemInventory,
		character: CharacterData):
	var screen = load(SHOP_SCREEN_SCENE).instantiate()
	add_child_autofree(screen)
	var billing := FakeBilling.new()
	add_child_autofree(billing)
	screen.setup(ledger, SkillInventory.new(), PaidUnlockInventory.new(),
		billing, character, inv)
	return screen

func test_buy_gear_debits_gold_and_grants_item():
	var ledger := CurrencyLedger.new()
	ledger.credit(1500, CurrencyLedger.Currency.GOLD)
	var inv := ItemInventory.new()
	var screen := _make_screen(ledger, inv, _wizard())
	screen._on_buy_pressed("shop_archmage_staff")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 500,
		"1000 gold deducted for epic")
	assert_eq(inv.bag_items().size(), 1)
	assert_eq(inv.bag_items()[0].id, "shop_archmage_staff")

func test_insufficient_gold_does_not_grant_or_debit():
	var ledger := CurrencyLedger.new()
	ledger.credit(500, CurrencyLedger.Currency.GOLD)
	var inv := ItemInventory.new()
	var screen := _make_screen(ledger, inv, _wizard())
	screen._on_buy_pressed("shop_archmage_staff")  # 1000 gold required
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 500,
		"insufficient gold must not be debited")
	assert_eq(inv.bag_items().size(), 0)

func test_buy_common_gear_costs_50_gold():
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GOLD)
	var inv := ItemInventory.new()
	var screen := _make_screen(ledger, inv, _wizard())
	screen._on_buy_pressed("shop_apprentice_garb")  # COMMON wizard gear
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 50)
	assert_eq(inv.bag_items().size(), 1)
