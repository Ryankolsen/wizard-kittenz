extends GutTest

# DailyStreakEngine (PRD #237 / issue #241). Pure resolver over
# (save_data, today_date) returning an action + day + reward. Replaces the
# flat 10-gem DailyLoginBonus. Engine writes streak_day + last_login_date
# on a claim/reset but never touches the currency ledger or XP tracker —
# that routing belongs to the reward applier (#242).

func test_first_login_claims_day_one():
	var save := KittenSaveData.new()
	# last_login_date defaults to "" and streak_day defaults to 0.
	var result := DailyStreakEngine.resolve(save, "2026-05-13")
	assert_eq(result["action"], DailyStreakEngine.Action.CLAIM)
	assert_eq(result["day"], 1)
	assert_eq(result["reward"]["type"], DailyStreakSchedule.RewardType.GOLD)
	assert_eq(result["reward"]["amount"], 50)
	assert_eq(save.streak_day, 1)
	assert_eq(save.last_login_date, "2026-05-13")

func test_same_day_is_already_claimed():
	var save := KittenSaveData.new()
	save.streak_day = 5
	save.last_login_date = "2026-05-13"
	var result := DailyStreakEngine.resolve(save, "2026-05-13")
	assert_eq(result["action"], DailyStreakEngine.Action.ALREADY_CLAIMED)
	assert_eq(result["day"], 5)
	# No state change on a same-day re-call.
	assert_eq(save.streak_day, 5)
	assert_eq(save.last_login_date, "2026-05-13")

func test_consecutive_day_advances():
	var save := KittenSaveData.new()
	save.streak_day = 6
	save.last_login_date = "2026-05-13"
	var result := DailyStreakEngine.resolve(save, "2026-05-14")
	assert_eq(result["action"], DailyStreakEngine.Action.CLAIM)
	assert_eq(result["day"], 7)
	# Day 7: GOLD slot, 3rd occurrence → 50 + 25*2 = 100.
	assert_eq(result["reward"]["type"], DailyStreakSchedule.RewardType.GOLD)
	assert_eq(result["reward"]["amount"], 100)
	assert_eq(save.streak_day, 7)
	assert_eq(save.last_login_date, "2026-05-14")

func test_missed_day_resets_with_broken_reason():
	var save := KittenSaveData.new()
	save.streak_day = 9
	save.last_login_date = "2026-05-13"
	var result := DailyStreakEngine.resolve(save, "2026-05-16")
	assert_eq(result["action"], DailyStreakEngine.Action.RESET_THEN_CLAIM)
	assert_eq(result["day"], 1)
	assert_eq(result["reset_reason"], DailyStreakEngine.ResetReason.MISSED)
	assert_eq(result["previous_streak"], 9)
	assert_eq(save.streak_day, 1)
	assert_eq(save.last_login_date, "2026-05-16")

func test_day_after_thirty_resets_silently():
	var save := KittenSaveData.new()
	save.streak_day = 30
	save.last_login_date = "2026-05-13"
	var result := DailyStreakEngine.resolve(save, "2026-05-14")
	assert_eq(result["action"], DailyStreakEngine.Action.RESET_THEN_CLAIM)
	assert_eq(result["day"], 1)
	# Cycle completion is a distinct reason from a missed-day break — the
	# popup uses this to suppress the "streak broken" framing.
	assert_eq(result["reset_reason"], DailyStreakEngine.ResetReason.CYCLE_COMPLETE)
	assert_eq(result["previous_streak"], 30)
	assert_eq(save.streak_day, 1)
	assert_eq(save.last_login_date, "2026-05-14")

func test_engine_does_not_touch_ledger():
	var save := KittenSaveData.new()
	var ledger := CurrencyLedger.new()
	var result := DailyStreakEngine.resolve(save, "2026-05-13")
	assert_eq(result["action"], DailyStreakEngine.Action.CLAIM)
	# Engine writes save bookkeeping but never credits currency.
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)

func test_null_save_is_safe_noop():
	var result: Dictionary = DailyStreakEngine.resolve(null, "2026-05-13")
	assert_eq(result["action"], DailyStreakEngine.Action.ALREADY_CLAIMED)
	assert_eq(result["day"], 0)

func test_empty_today_is_safe_noop():
	var save := KittenSaveData.new()
	save.streak_day = 4
	save.last_login_date = "2026-05-13"
	var result := DailyStreakEngine.resolve(save, "")
	assert_eq(result["action"], DailyStreakEngine.Action.ALREADY_CLAIMED)
	# No state change.
	assert_eq(save.streak_day, 4)
	assert_eq(save.last_login_date, "2026-05-13")

func test_null_today_is_safe_noop():
	var save := KittenSaveData.new()
	var result: Dictionary = DailyStreakEngine.resolve(save, null)
	assert_eq(result["action"], DailyStreakEngine.Action.ALREADY_CLAIMED)
	assert_eq(save.last_login_date, "")
	assert_eq(save.streak_day, 0)

func test_month_boundary_consecutive_day_advances():
	# Last day of May → first day of June is gap == 1, not a reset.
	var save := KittenSaveData.new()
	save.streak_day = 3
	save.last_login_date = "2026-05-31"
	var result := DailyStreakEngine.resolve(save, "2026-06-01")
	assert_eq(result["action"], DailyStreakEngine.Action.CLAIM)
	assert_eq(result["day"], 4)

func test_legacy_save_with_date_but_zero_streak_starts_at_day_one():
	# Save from before #239 shipped: last_login_date populated but
	# streak_day defaults to 0. Treat as first-ever streak login.
	var save := KittenSaveData.from_dict({"last_login_date": "2026-05-12"})
	assert_eq(save.streak_day, 0)
	var result := DailyStreakEngine.resolve(save, "2026-05-13")
	assert_eq(result["action"], DailyStreakEngine.Action.CLAIM)
	assert_eq(result["day"], 1)
	assert_eq(save.streak_day, 1)
