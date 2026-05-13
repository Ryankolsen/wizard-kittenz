extends GutTest

# DailyLoginBonus (PRD #53 / issue #68). Awards a small Gem bonus once
# per calendar day on session start. Pure helper with injectable
# today_date so tests don't depend on the wall clock.

func test_new_day_credits_gem_reward_and_updates_date():
	var save := KittenSaveData.new()
	save.last_login_date = "2026-05-12"
	var ledger := CurrencyLedger.new()
	var awarded := DailyLoginBonus.try_award(save, ledger, "2026-05-13")
	assert_true(awarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), DailyLoginBonus.DAILY_LOGIN_GEM_REWARD)
	assert_eq(save.last_login_date, "2026-05-13")

func test_same_day_is_noop():
	var save := KittenSaveData.new()
	save.last_login_date = "2026-05-13"
	var ledger := CurrencyLedger.new()
	var awarded := DailyLoginBonus.try_award(save, ledger, "2026-05-13")
	assert_false(awarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)
	assert_eq(save.last_login_date, "2026-05-13")

func test_first_ever_login_awards_bonus():
	var save := KittenSaveData.new()
	# last_login_date defaults to "" — never logged in.
	assert_eq(save.last_login_date, "")
	var ledger := CurrencyLedger.new()
	var awarded := DailyLoginBonus.try_award(save, ledger, "2026-05-13")
	assert_true(awarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), DailyLoginBonus.DAILY_LOGIN_GEM_REWARD)
	assert_eq(save.last_login_date, "2026-05-13")

func test_idempotent_on_same_day_double_call():
	var save := KittenSaveData.new()
	var ledger := CurrencyLedger.new()
	var first := DailyLoginBonus.try_award(save, ledger, "2026-05-13")
	var second := DailyLoginBonus.try_award(save, ledger, "2026-05-13")
	assert_true(first)
	assert_false(second)
	# Balance equals one reward, not double.
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), DailyLoginBonus.DAILY_LOGIN_GEM_REWARD)

func test_save_load_round_trip_preserves_last_login_date():
	var save := KittenSaveData.new()
	save.last_login_date = "2026-05-13"
	var d := save.to_dict()
	var reloaded := KittenSaveData.from_dict(d)
	assert_eq(reloaded.last_login_date, "2026-05-13")
	# After reload, a same-day call is still a no-op.
	var ledger := CurrencyLedger.new()
	var awarded := DailyLoginBonus.try_award(reloaded, ledger, "2026-05-13")
	assert_false(awarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)

func test_legacy_save_defaults_last_login_date_to_empty():
	# Save dict missing the field (legacy) — from_dict defaults to "".
	var reloaded := KittenSaveData.from_dict({})
	assert_eq(reloaded.last_login_date, "")
	# Legacy save then triggers a first-day award.
	var ledger := CurrencyLedger.new()
	var awarded := DailyLoginBonus.try_award(reloaded, ledger, "2026-05-13")
	assert_true(awarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), DailyLoginBonus.DAILY_LOGIN_GEM_REWARD)

func test_null_save_data_is_safe_noop():
	var ledger := CurrencyLedger.new()
	var awarded := DailyLoginBonus.try_award(null, ledger, "2026-05-13")
	assert_false(awarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)

func test_null_ledger_is_safe_noop_and_does_not_advance_date():
	var save := KittenSaveData.new()
	var awarded := DailyLoginBonus.try_award(save, null, "2026-05-13")
	assert_false(awarded)
	assert_eq(save.last_login_date, "")

func test_empty_today_date_is_rejected():
	var save := KittenSaveData.new()
	var ledger := CurrencyLedger.new()
	var awarded := DailyLoginBonus.try_award(save, ledger, "")
	assert_false(awarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)
	assert_eq(save.last_login_date, "")

func test_reward_constant_matches_pin():
	# Pin so a tuning change is a deliberate edit.
	assert_eq(DailyLoginBonus.DAILY_LOGIN_GEM_REWARD, 10)
