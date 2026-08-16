extends GutTest

# Issue #494: pure-data HoomanRentalService. Owns rental state (paid-for-floor)
# and debits CurrencyLedger on activation. No SceneTree, same style as
# test_npc_option.gd / test_currency_ledger.gd.

func test_activate_debits_gold_and_marks_floor_active():
	var ledger := CurrencyLedger.new()
	ledger.credit(HoomanRentalService.RENT_COST_GOLD, CurrencyLedger.Currency.GOLD)
	var service := HoomanRentalService.new()
	assert_true(service.activate(3, ledger))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)
	assert_true(service.is_active_for_floor(3))


func test_is_active_for_floor_false_on_different_floor():
	var ledger := CurrencyLedger.new()
	ledger.credit(HoomanRentalService.RENT_COST_GOLD, CurrencyLedger.Currency.GOLD)
	var service := HoomanRentalService.new()
	service.activate(3, ledger)
	assert_false(service.is_active_for_floor(4), "renewal is required per floor")


func test_is_active_for_floor_false_before_any_activation():
	var service := HoomanRentalService.new()
	assert_false(service.is_active_for_floor(1))


func test_activate_fails_when_insufficient_gold():
	var ledger := CurrencyLedger.new()
	var service := HoomanRentalService.new()
	assert_false(service.activate(1, ledger))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)
	assert_false(service.is_active_for_floor(1))


func test_clear_resets_active_state():
	var ledger := CurrencyLedger.new()
	ledger.credit(HoomanRentalService.RENT_COST_GOLD, CurrencyLedger.Currency.GOLD)
	var service := HoomanRentalService.new()
	service.activate(2, ledger)
	service.clear()
	assert_false(service.is_active_for_floor(2))
