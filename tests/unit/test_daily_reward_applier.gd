extends GutTest

# DailyRewardApplier (PRD #237 / issue #242). Thin router that takes a
# {type, amount} reward from DailyStreakSchedule and credits the matching
# subsystem. Uses real CurrencyLedger + OfflineXPTracker instances — both
# are pure RefCounted with no autoloads, so no mocks needed.

var _ledger: CurrencyLedger
var _tracker: OfflineXPTracker

func before_each():
	_ledger = CurrencyLedger.new()
	_tracker = OfflineXPTracker.new()

func test_gold_reward_credits_ledger():
	DailyRewardApplier.apply(
		{"type": DailyStreakSchedule.RewardType.GOLD, "amount": 50},
		_ledger, _tracker)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GOLD), 50)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GEM), 0)
	assert_eq(_tracker.pending_xp, 0)

func test_gem_reward_credits_ledger():
	DailyRewardApplier.apply(
		{"type": DailyStreakSchedule.RewardType.GEM, "amount": 11},
		_ledger, _tracker)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GEM), 11)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GOLD), 0)
	assert_eq(_tracker.pending_xp, 0)

func test_xp_reward_records_offline_tracker():
	DailyRewardApplier.apply(
		{"type": DailyStreakSchedule.RewardType.XP, "amount": 40},
		_ledger, _tracker)
	assert_eq(_tracker.pending_xp, 40)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GOLD), 0)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GEM), 0)

func test_jackpot_gem_credits_250():
	# Day-30 jackpot comes through the schedule as {GEM, 250}; the applier
	# treats it like any other GEM credit (no special-casing).
	var jackpot := DailyStreakSchedule.reward_for(30)
	DailyRewardApplier.apply(jackpot, _ledger, _tracker)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GEM), 250)

func test_nonpositive_and_unknown_type_are_noops():
	DailyRewardApplier.apply(
		{"type": DailyStreakSchedule.RewardType.GOLD, "amount": 0},
		_ledger, _tracker)
	DailyRewardApplier.apply(
		{"type": DailyStreakSchedule.RewardType.GOLD, "amount": -5},
		_ledger, _tracker)
	DailyRewardApplier.apply({"type": 999, "amount": 50}, _ledger, _tracker)
	DailyRewardApplier.apply({}, _ledger, _tracker)
	DailyRewardApplier.apply({"type": DailyStreakSchedule.RewardType.GOLD}, _ledger, _tracker)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GOLD), 0)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GEM), 0)
	assert_eq(_tracker.pending_xp, 0)

func test_engine_result_reward_routes_end_to_end():
	# Sanity-check the engine → applier seam: a first-login claim returns
	# {GOLD, 50}, which the applier should land on the ledger unchanged.
	var save := KittenSaveData.new()
	var result := DailyStreakEngine.resolve(save, "2026-05-13")
	DailyRewardApplier.apply(result["reward"], _ledger, _tracker)
	assert_eq(_ledger.balance(CurrencyLedger.Currency.GOLD), 50)
