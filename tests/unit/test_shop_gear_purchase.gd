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
		character: CharacterData) -> ShopScreen:
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

# --- Slice 3 (#234): gear ownership rule ------------------------------------

# 1. _is_owned is true when the item is in the bag.
func test_is_owned_true_when_id_in_bag():
	var ledger := CurrencyLedger.new()
	var inv := ItemInventory.new()
	inv.add_to_bag(ItemCatalog.find("shop_apprentice_garb"))
	var screen := _make_screen(ledger, inv, _wizard())
	var item := ShopCatalog.find("shop_apprentice_garb")
	assert_true(screen._is_owned(item))

# 2. _is_owned is false when the bag is empty.
func test_is_owned_false_when_bag_empty():
	var ledger := CurrencyLedger.new()
	var screen := _make_screen(ledger, ItemInventory.new(), _wizard())
	var item := ShopCatalog.find("shop_apprentice_garb")
	assert_false(screen._is_owned(item))

# 3. After remove_from_bag, the row is re-buyable.
func test_is_owned_false_after_remove_from_bag():
	var ledger := CurrencyLedger.new()
	var inv := ItemInventory.new()
	inv.add_to_bag(ItemCatalog.find("shop_apprentice_garb"))
	inv.remove_from_bag("shop_apprentice_garb")
	var screen := _make_screen(ledger, inv, _wizard())
	var item := ShopCatalog.find("shop_apprentice_garb")
	assert_false(screen._is_owned(item))

# 4. _is_owned is true when the item is equipped (not in bag).
func test_is_owned_true_when_equipped():
	var ledger := CurrencyLedger.new()
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("shop_apprentice_garb"))
	var screen := _make_screen(ledger, inv, _wizard())
	var item := ShopCatalog.find("shop_apprentice_garb")
	assert_true(screen._is_owned(item))

func _row_button(screen: ShopScreen, product_id: String) -> Button:
	var row: HBoxContainer = screen._rows_by_product.get(product_id)
	if row == null:
		return null
	for c in row.get_children():
		if c is Button:
			return c
	return null

# 6. Adding the gear to the bag live-flips the row to "Owned" + disabled
# without rebuilding the shop.
func test_row_flips_to_owned_live_on_inventory_change():
	var ledger := CurrencyLedger.new()
	var inv := ItemInventory.new()
	var screen := _make_screen(ledger, inv, _wizard())
	var btn := _row_button(screen, "shop_apprentice_garb")
	assert_eq(btn.text, "Buy")
	inv.add_to_bag(ItemCatalog.find("shop_apprentice_garb"))
	assert_eq(btn.text, "Owned")
	assert_true(btn.disabled)

# 7. Full tracer-bullet: end-to-end purchase via _on_buy_pressed flips the
# row to Owned with no extra plumbing.
func test_successful_purchase_flips_row_to_owned():
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GOLD)
	var inv := ItemInventory.new()
	var screen := _make_screen(ledger, inv, _wizard())
	var btn := _row_button(screen, "shop_apprentice_garb")
	assert_eq(btn.text, "Buy")
	screen._on_buy_pressed("shop_apprentice_garb")
	assert_eq(btn.text, "Owned")
	assert_true(btn.disabled)
