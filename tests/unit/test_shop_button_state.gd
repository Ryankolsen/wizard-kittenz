extends GutTest

# Slice 2 of PRD #231: Buy button is visibly disabled when the player can't
# afford a row, and the disabled state updates live as balance changes. Owned
# precedence over unaffordable is also locked in here.

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

func _make_screen(ledger: CurrencyLedger, inv: ItemInventory,
		character: CharacterData):
	var screen = load(SHOP_SCREEN_SCENE).instantiate()
	add_child_autofree(screen)
	var billing := FakeBilling.new()
	add_child_autofree(billing)
	screen.setup(ledger, SkillInventory.new(), PaidUnlockInventory.new(),
		billing, character, inv)
	return screen

func _row_button(screen, product_id: String) -> Button:
	var row: HBoxContainer = screen._rows_by_product.get(product_id)
	if row == null:
		return null
	for c in row.get_children():
		if c is Button:
			return c
	return null

# 1. Insufficient balance → button disabled.
func test_buy_disabled_when_balance_below_price():
	var ledger := CurrencyLedger.new()
	ledger.credit(30, CurrencyLedger.Currency.GOLD)
	var screen = _make_screen(ledger, ItemInventory.new(), _wizard())
	var btn := _row_button(screen, "shop_apprentice_garb")  # 50G common
	assert_not_null(btn, "row should be rendered for wizard")
	assert_true(btn.disabled, "Buy must be disabled when ledger < price")
	assert_eq(btn.text, "Buy")

# 2. Sufficient balance → button enabled.
func test_buy_enabled_when_balance_meets_price():
	var ledger := CurrencyLedger.new()
	ledger.credit(50, CurrencyLedger.Currency.GOLD)
	var screen = _make_screen(ledger, ItemInventory.new(), _wizard())
	var btn := _row_button(screen, "shop_apprentice_garb")
	assert_false(btn.disabled, "Buy must enable when ledger >= price")

# 3. Live update — debit triggers _on_balance_changed, all rows re-render.
func test_balance_change_re_renders_all_rows_live():
	var ledger := CurrencyLedger.new()
	ledger.credit(1500, CurrencyLedger.Currency.GOLD)
	var screen = _make_screen(ledger, ItemInventory.new(), _wizard())
	var common_btn := _row_button(screen, "shop_apprentice_garb")  # 50G
	var epic_btn := _row_button(screen, "shop_archmage_staff")     # 1000G
	assert_false(common_btn.disabled)
	assert_false(epic_btn.disabled)
	ledger.debit(1450, CurrencyLedger.Currency.GOLD)  # → 50G left
	assert_false(common_btn.disabled, "50G row stays affordable")
	assert_true(epic_btn.disabled, "1000G row must flip to disabled live")

# Owned-class character — _is_owned returns true for the tier-2 upgrade row
# that targets this class. Used as a stand-in for "row already says Owned"
# until #234 lands gear-bag ownership.
func _wizard_cat(level: int = 11) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_CAT, "w")
	c.level = level
	return c

# 4. Owned beats unaffordable: an owned upgrade row stays "Owned" + disabled
# even when the player can afford it. The wizard_cat character already sits
# at the upgrade's target tier, so _is_owned returns true.
func test_owned_beats_affordable_label():
	var ledger := CurrencyLedger.new()
	ledger.credit(10000, CurrencyLedger.Currency.GEM)
	var screen = _make_screen(ledger, ItemInventory.new(), _wizard_cat())
	var btn := _row_button(screen, PurchaseRegistry.UPGRADE_WIZARD_KITTEN_WIZARD_CAT)
	assert_not_null(btn, "upgrade row should render")
	assert_eq(btn.text, "Owned")
	assert_true(btn.disabled)

# 5. Live updates don't flip an Owned row back to "Buy".
func test_owned_row_stays_owned_after_balance_change():
	var ledger := CurrencyLedger.new()
	ledger.credit(10000, CurrencyLedger.Currency.GEM)
	var screen = _make_screen(ledger, ItemInventory.new(), _wizard_cat())
	ledger.debit(1, CurrencyLedger.Currency.GEM)  # triggers balance_changed
	var btn := _row_button(screen, PurchaseRegistry.UPGRADE_WIZARD_KITTEN_WIZARD_CAT)
	assert_eq(btn.text, "Owned")
	assert_true(btn.disabled)
