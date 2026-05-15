extends GutTest

# ShopScreen purchase flow wiring (PRD #53 / issue #71). Two dispatch shapes:
# soft-currency (Gold/Gem) rows debit then PurchaseGrantHandler.handle; gem
# bundles go through BillingManager.start_purchase and grant on the
# purchase_succeeded signal. Tests instance the scene so @onready labels +
# error_label exist, but inject a FakeBilling so we don't hit the real
# autoload (which would no-op on desktop anyway).

const SHOP_SCREEN_SCENE := "res://scenes/shop_screen.tscn"

class FakeBilling:
	extends Node

	signal purchase_succeeded(product_id: String)
	signal purchase_failed(product_id: String)

	var last_start_purchase_id: String = ""

	func start_purchase(product_id: String) -> void:
		last_start_purchase_id = product_id

func _make_screen(ledger: CurrencyLedger, skill_inv: SkillInventory,
		paid_unlocks: PaidUnlockInventory, billing: FakeBilling,
		character: CharacterData = null):
	var screen = load(SHOP_SCREEN_SCENE).instantiate()
	add_child_autofree(screen)
	add_child_autofree(billing)
	screen.setup(ledger, skill_inv, paid_unlocks, billing, character)
	return screen

func _new_billing() -> FakeBilling:
	return FakeBilling.new()

# 1. Core wiring — buying a Gold skill row debits Gold and marks owned.
func test_buy_skill_debits_gold_and_grants_skill():
	var ledger := CurrencyLedger.new()
	ledger.credit(500, CurrencyLedger.Currency.GOLD)
	var inv := SkillInventory.new()
	var screen := _make_screen(ledger, inv, PaidUnlockInventory.new(), _new_billing())
	screen._on_buy_pressed(PurchaseRegistry.SKILL_UNLOCK_FIREBALL)
	assert_true(inv.has_skill("fireball"))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 250)

# 2. Insufficient funds — debit fails, skill not granted, no error label.
func test_insufficient_funds_does_not_grant():
	var ledger := CurrencyLedger.new()
	var inv := SkillInventory.new()
	var screen := _make_screen(ledger, inv, PaidUnlockInventory.new(), _new_billing())
	screen._on_buy_pressed(PurchaseRegistry.SKILL_UNLOCK_FIREBALL)
	assert_false(inv.has_skill("fireball"))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)
	assert_false(screen.error_label.visible)

# 3. Gem bundle row routes to BillingManager.start_purchase.
func test_gem_bundle_triggers_billing_start_purchase():
	var billing := _new_billing()
	var screen := _make_screen(CurrencyLedger.new(), SkillInventory.new(),
		PaidUnlockInventory.new(), billing)
	screen._on_buy_pressed(PurchaseRegistry.GEM_BUNDLE_STARTER)
	assert_eq(billing.last_start_purchase_id, PurchaseRegistry.GEM_BUNDLE_STARTER)

# 4. purchase_succeeded credits the configured Gem amount.
func test_purchase_succeeded_credits_gems():
	var ledger := CurrencyLedger.new()
	var billing := _new_billing()
	var screen := _make_screen(ledger, SkillInventory.new(),
		PaidUnlockInventory.new(), billing)
	billing.purchase_succeeded.emit(PurchaseRegistry.GEM_BUNDLE_STARTER)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 100)
	assert_false(screen.error_label.visible)

# 5. purchase_failed surfaces an error label.
func test_purchase_failed_shows_error_label():
	var billing := _new_billing()
	var screen := _make_screen(CurrencyLedger.new(), SkillInventory.new(),
		PaidUnlockInventory.new(), billing)
	billing.purchase_failed.emit(PurchaseRegistry.GEM_BUNDLE_STARTER)
	assert_true(screen.error_label.visible)
	assert_true(screen.error_label.text.to_lower().find("failed") >= 0)

# Owned rows can't be re-bought (button disabled / Owned state).
func test_already_owned_skill_buy_is_noop():
	var ledger := CurrencyLedger.new()
	ledger.credit(1000, CurrencyLedger.Currency.GOLD)
	var inv := SkillInventory.new()
	inv.grant("fireball")
	var screen := _make_screen(ledger, inv, PaidUnlockInventory.new(), _new_billing())
	screen._on_buy_pressed(PurchaseRegistry.SKILL_UNLOCK_FIREBALL)
	# Balance untouched — re-buy short-circuited.
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 1000)

# Class-unlock soft-currency path grants into PaidUnlockInventory.
func test_buy_class_unlock_grants_paid_unlock():
	var ledger := CurrencyLedger.new()
	ledger.credit(1000, CurrencyLedger.Currency.GEM)
	var paid := PaidUnlockInventory.new()
	var screen := _make_screen(ledger, SkillInventory.new(), paid, _new_billing())
	screen._on_buy_pressed(PurchaseRegistry.CLASS_UNLOCK_CHONK_KITTEN)
	assert_true(paid.has_unlock("battle_kitten"))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 500)

# After a successful purchase the row's button text flips to "Owned".
func test_row_refreshes_to_owned_after_purchase():
	var ledger := CurrencyLedger.new()
	ledger.credit(500, CurrencyLedger.Currency.GOLD)
	var inv := SkillInventory.new()
	var screen := _make_screen(ledger, inv, PaidUnlockInventory.new(), _new_billing())
	screen._on_buy_pressed(PurchaseRegistry.SKILL_UNLOCK_FIREBALL)
	var row: HBoxContainer = screen._rows_by_product[PurchaseRegistry.SKILL_UNLOCK_FIREBALL]
	var btn: Button = null
	for c in row.get_children():
		if c is Button:
			btn = c
			break
	assert_not_null(btn)
	assert_eq(btn.text, "Owned")
	assert_true(btn.disabled)

# Gem-bundle replay (BillingManager re-emits succeeded on restart) is no-op
# the second time thanks to CurrencyLedger.try_grant_bundle's session guard.
func test_purchase_succeeded_replay_does_not_double_credit():
	var ledger := CurrencyLedger.new()
	var billing := _new_billing()
	var _screen := _make_screen(ledger, SkillInventory.new(),
		PaidUnlockInventory.new(), billing)
	billing.purchase_succeeded.emit(PurchaseRegistry.GEM_BUNDLE_STARTER)
	billing.purchase_succeeded.emit(PurchaseRegistry.GEM_BUNDLE_STARTER)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 100)
