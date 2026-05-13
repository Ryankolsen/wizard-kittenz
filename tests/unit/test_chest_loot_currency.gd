extends GutTest

# Tests for PRD #53 / issue #66 — chest loot credits CurrencyLedger.
# Standard chests pay Gold; rare chests pay Gems. Either way, the
# chest is single-use — a second open() is a no-op.

func test_standard_chest_open_credits_gold():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.STANDARD)
	var ok := chest.open(ledger)
	assert_true(ok)
	assert_true(ledger.balance(CurrencyLedger.Currency.GOLD) > 0)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD)

func test_standard_chest_does_not_credit_gems():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.STANDARD)
	chest.open(ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)

func test_rare_chest_open_credits_gems():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.RARE)
	var ok := chest.open(ledger)
	assert_true(ok)
	assert_true(ledger.balance(CurrencyLedger.Currency.GEM) > 0)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), Chest.RARE_GEMS)

func test_rare_chest_does_not_credit_gold():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.RARE)
	chest.open(ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)

func test_double_open_is_a_noop_standard():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.STANDARD)
	chest.open(ledger)
	var balance_after_first := ledger.balance(CurrencyLedger.Currency.GOLD)
	var ok2 := chest.open(ledger)
	assert_false(ok2)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), balance_after_first)

func test_double_open_is_a_noop_rare():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.RARE)
	chest.open(ledger)
	var balance_after_first := ledger.balance(CurrencyLedger.Currency.GEM)
	var ok2 := chest.open(ledger)
	assert_false(ok2)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), balance_after_first)

func test_open_sets_is_opened():
	var chest := Chest.make(Chest.Kind.STANDARD)
	assert_false(chest.is_opened())
	chest.open(CurrencyLedger.new())
	assert_true(chest.is_opened())

func test_open_with_null_ledger_does_not_consume_chest():
	var chest := Chest.make(Chest.Kind.STANDARD)
	var ok := chest.open(null)
	assert_false(ok)
	assert_false(chest.is_opened())
	# Should still be openable afterwards with a real ledger.
	var ledger := CurrencyLedger.new()
	assert_true(chest.open(ledger))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD)

func test_amounts_are_constants_not_magic():
	# Pin the constants so a future tuning pass touches one place.
	assert_eq(Chest.STANDARD_GOLD, 25)
	assert_eq(Chest.RARE_GEMS, 5)
