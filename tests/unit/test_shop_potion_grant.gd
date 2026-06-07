extends GutTest

# Slice 5 of PRD #358 (issue #361). The shop-side of the potion spine — three
# Gold-priced POTION-category rows wired into PurchaseGrantHandler so a Buy
# press lands in ConsumableInventory. Mirrors test_purchase_grant_handler.gd's
# handler-in-isolation style: the dispatch is what's under test, not the UI.

# --- Core wiring ------------------------------------------------------------

func test_potion_purchase_credits_consumable_inventory():
	# AC: "Buying a potion debits gold and credits the matching
	# ConsumableInventory count by +1". The handler side: routing
	# "health_potion" through grant lands as count_of("health_potion") == 1.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var inv := ConsumableInventory.new()
	var ok := PurchaseGrantHandler.handle(
		"health_potion", c, null, null, null, null, null, inv)
	assert_true(ok, "potion grant returns true on success")
	assert_eq(inv.count_of("health_potion"), 1,
		"one purchase -> count 1")

func test_potion_grant_type_is_potion():
	# Pins the grant_type_for dispatch: every PotionCatalog id routes to
	# GRANT_POTION so the handler's match-arm fires. Catches a future catalog
	# add that forgets to wire its id into the registry.
	for potion: PotionDefinition in PotionCatalog.all():
		assert_eq(PurchaseRegistry.grant_type_for(potion.id),
			PurchaseRegistry.GRANT_POTION,
			"potion %s routes to GRANT_POTION" % potion.id)

# --- Content details --------------------------------------------------------

func test_catalog_has_three_potion_rows():
	# AC: "The shop catalog exposes three POTION-category rows". Surface the
	# rows independent of any character_class so the shop never hides potions
	# behind class-gated visibility.
	var potion_rows: Array = []
	for item: ShopCatalogItem in ShopCatalog.items():
		if item.category == ShopCatalogItem.CATEGORY_POTION:
			potion_rows.append(item)
	assert_eq(potion_rows.size(), 3,
		"three POTION rows (health, mana, shield)")

func test_potion_rows_are_gold_with_positive_price():
	# AC: "currency = GOLD, with prices". A potion priced at 0 would let a
	# broke player infinitely stack — pin price > 0 so a content tuning pass
	# can't accidentally make it free.
	for potion: PotionDefinition in PotionCatalog.all():
		var row := ShopCatalog.find(potion.id)
		assert_not_null(row, "ShopCatalog.find resolves %s" % potion.id)
		assert_eq(row.category, ShopCatalogItem.CATEGORY_POTION)
		assert_eq(row.currency_type, CurrencyLedger.Currency.GOLD)
		assert_true(row.price > 0,
			"%s has a positive Gold price" % potion.id)

func test_catalog_find_resolves_each_potion_id():
	# Pins the lazy-lookup path: ShopCatalog.find resolves every potion id
	# whether or not it walked the full items() list first. Mirrors the gear
	# lazy path so the shop refresh-by-product-id flow works for potions too.
	for potion: PotionDefinition in PotionCatalog.all():
		assert_not_null(ShopCatalog.find(potion.id),
			"find(%s) non-null" % potion.id)

# --- Edge cases -------------------------------------------------------------

func test_potion_purchase_is_repeatable_no_replay_guard():
	# AC: "Purchases are repeatable (buying twice yields count 2; no replay
	# guard)". Unlike class/cosmetic grants, the second call must land — the
	# potion belt is a consumable spend loop, not a permanent unlock.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var inv := ConsumableInventory.new()
	PurchaseGrantHandler.handle("health_potion", c, null, null, null, null, null, inv)
	PurchaseGrantHandler.handle("health_potion", c, null, null, null, null, null, inv)
	assert_eq(inv.count_of("health_potion"), 2,
		"second purchase increments rather than no-ops")

func test_insufficient_gold_no_credit():
	# AC mirror: the soft-currency debit path is the gate. If debit() fails
	# (price > balance), the caller never reaches handle() and no credit
	# lands. Models the ShopScreen._on_buy_pressed sequence in isolation so
	# the contract holds without booting the scene tree.
	var ledger := CurrencyLedger.new()
	# 1 Gold — guaranteed under any positive potion price.
	ledger.credit(1, CurrencyLedger.Currency.GOLD)
	var inv := ConsumableInventory.new()
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var row := ShopCatalog.find("health_potion")
	var debited := ledger.debit(row.price, CurrencyLedger.Currency.GOLD)
	assert_false(debited, "debit fails on insufficient funds")
	# Caller bails before handle() — count must remain 0.
	assert_eq(inv.count_of("health_potion"), 0,
		"no credit when debit failed")
	# And the no-debit branch never mutated the ledger.
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 1,
		"failed debit leaves balance untouched")

func test_null_consumable_inventory_is_safe():
	# Mirrors the other handler paths' null-safety contract: a legacy call
	# site that forgets to pass the inventory gets "no grant landed" rather
	# than a crash, so the shop can refund the Gold debit instead of eating
	# the currency on a wiring bug.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var ok := PurchaseGrantHandler.handle(
		"health_potion", c, null, null, null, null, null, null)
	assert_false(ok, "null inventory -> no grant, no crash")

func test_unknown_potion_id_routes_via_dispatch_not_potion_branch():
	# Defensive: a bogus id must NOT be dispatched as a potion grant. Catches
	# a future "grant_type_for falls through to GRANT_POTION by accident"
	# regression that would let any unknown string mint a potion count.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var inv := ConsumableInventory.new()
	var ok := PurchaseGrantHandler.handle(
		"not_a_real_potion", c, null, null, null, null, null, inv)
	assert_false(ok)
	assert_eq(inv.count_of("not_a_real_potion"), 0)
