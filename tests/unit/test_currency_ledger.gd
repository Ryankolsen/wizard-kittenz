extends GutTest

# CurrencyLedger (PRD #53 / issue #63). Owns Gold + Gem balances with a
# never-negative invariant + balance_changed signal. Round-trips through
# KittenSaveData/SaveManager so balances persist across sessions.

const TMP_PATH := "user://test_currency.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func test_credit_increases_balance():
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GOLD)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 100)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)

func test_debit_decreases_balance():
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GOLD)
	var ok := ledger.debit(30, CurrencyLedger.Currency.GOLD)
	assert_true(ok)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 70)

func test_debit_insufficient_funds_returns_false_and_no_mutation():
	var ledger := CurrencyLedger.new()
	ledger.credit(50, CurrencyLedger.Currency.GEM)
	var ok := ledger.debit(51, CurrencyLedger.Currency.GEM)
	assert_false(ok)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 50)

func test_signal_fires_on_credit():
	var ledger := CurrencyLedger.new()
	watch_signals(ledger)
	ledger.credit(10, CurrencyLedger.Currency.GEM)
	assert_signal_emitted_with_parameters(ledger, "balance_changed", [CurrencyLedger.Currency.GEM, 10])

func test_signal_fires_on_successful_debit():
	var ledger := CurrencyLedger.new()
	ledger.credit(20, CurrencyLedger.Currency.GOLD)
	watch_signals(ledger)
	ledger.debit(5, CurrencyLedger.Currency.GOLD)
	assert_signal_emitted_with_parameters(ledger, "balance_changed", [CurrencyLedger.Currency.GOLD, 15])

func test_signal_does_not_fire_on_failed_debit():
	var ledger := CurrencyLedger.new()
	ledger.credit(5, CurrencyLedger.Currency.GOLD)
	watch_signals(ledger)
	ledger.debit(10, CurrencyLedger.Currency.GOLD)
	assert_signal_not_emitted(ledger, "balance_changed")

func test_save_load_round_trip_preserves_balances():
	var character := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var ledger := CurrencyLedger.new()
	ledger.credit(250, CurrencyLedger.Currency.GOLD)
	ledger.credit(17, CurrencyLedger.Currency.GEM)
	var err := SaveManager.save(character, TMP_PATH, null, null, null, null, null, {}, ledger)
	assert_eq(err, OK)
	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.gold_balance, 250)
	assert_eq(loaded.gem_balance, 17)
	var rebuilt := loaded.to_currency_ledger()
	assert_eq(rebuilt.balance(CurrencyLedger.Currency.GOLD), 250)
	assert_eq(rebuilt.balance(CurrencyLedger.Currency.GEM), 17)

func test_legacy_save_without_balances_defaults_to_zero():
	var d := {"character_name": "Old"}
	var s := KittenSaveData.from_dict(d)
	assert_eq(s.gold_balance, 0)
	assert_eq(s.gem_balance, 0)
