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

# --- Slice 3 of PRD #292: gear rows use the formatter -----------------------

func _wizard_character() -> CharacterData:
	var c := CharacterData.new()
	c.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	return c

func _labels_under(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Label:
			out.append(child)
		if child.get_child_count() > 0:
			out.append_array(_labels_under(child))
	return out

func test_gear_row_renders_one_label_per_bonus_line():
	# shop_archmage_staff is wizard-eligible Epic w/ magic_attack +10 — the
	# formatter emits "+10 Magic Attack", which the row must surface as a
	# distinct Label (not a run-on description).
	var screen := _make_screen(CurrencyLedger.new(), SkillInventory.new(),
		PaidUnlockInventory.new(), _new_billing(), _wizard_character())
	var row: HBoxContainer = screen._rows_by_product.get("shop_archmage_staff")
	assert_not_null(row, "expected a row for shop_archmage_staff")
	var labels := _labels_under(row)
	var saw_bonus := false
	for l in labels:
		if l.text == "+10 Magic Attack":
			saw_bonus = true
	assert_true(saw_bonus, "expected a Label with text '+10 Magic Attack'")

func test_gear_row_renders_tinted_rarity_label():
	# Rarity word lives on its own Label tinted with the formatter's EPIC color,
	# matching the equipped-tile borders (PRD #292 AC).
	var screen := _make_screen(CurrencyLedger.new(), SkillInventory.new(),
		PaidUnlockInventory.new(), _new_billing(), _wizard_character())
	var row: HBoxContainer = screen._rows_by_product.get("shop_archmage_staff")
	assert_not_null(row)
	var labels := _labels_under(row)
	var rarity_label: Label = null
	for l in labels:
		if l.text == "Epic":
			rarity_label = l
			break
	assert_not_null(rarity_label, "expected a Label with text 'Epic'")
	var expected := ItemDisplayFormatter.RARITY_COLORS[ItemData.Rarity.EPIC]
	assert_eq(rarity_label.get_theme_color("font_color"), expected,
		"rarity label must use formatter EPIC color")

func test_gear_row_does_not_show_runon_description():
	# Regression guard: AC "old attack +2.0 style description no longer appears
	# for gear" — no label may contain the raw stat key or the unhumanized
	# number format.
	var screen := _make_screen(CurrencyLedger.new(), SkillInventory.new(),
		PaidUnlockInventory.new(), _new_billing(), _wizard_character())
	var row: HBoxContainer = screen._rows_by_product.get("shop_archmage_staff")
	assert_not_null(row)
	for l in _labels_under(row):
		assert_eq(l.text.find("magic_attack"), -1,
			"gear row label leaked raw stat key: " + l.text)
		assert_eq(l.text.find("+10.0"), -1,
			"gear row label leaked unhumanized number: " + l.text)

func test_gem_bundle_row_still_uses_single_description_label():
	# Non-gear rows render their description verbatim — formatter must be
	# gear-only (regression guard).
	var screen := _make_screen(CurrencyLedger.new(), SkillInventory.new(),
		PaidUnlockInventory.new(), _new_billing(), _wizard_character())
	var row: HBoxContainer = screen._rows_by_product.get(PurchaseRegistry.GEM_BUNDLE_STARTER)
	assert_not_null(row)
	var saw_desc := false
	for l in _labels_under(row):
		if l.text.find("100 Gems") >= 0:
			saw_desc = true
	assert_true(saw_desc, "gem bundle should still render '100 Gems' description")

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
