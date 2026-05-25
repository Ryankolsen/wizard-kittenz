extends GutTest

# DailyStreakSchedule (PRD #237 / issue #238). Pure 30-day rotating
# reward table mapping streak day (1–30) → {type, amount}. No state,
# no clock, no ledger dependency.

func test_day_one_is_gold_fifty():
	var r := DailyStreakSchedule.reward_for(1)
	assert_eq(r.type, DailyStreakSchedule.RewardType.GOLD)
	assert_eq(r.amount, 50)

func test_type_rotates_gold_xp_gem():
	assert_eq(DailyStreakSchedule.reward_for(1).type, DailyStreakSchedule.RewardType.GOLD)
	assert_eq(DailyStreakSchedule.reward_for(2).type, DailyStreakSchedule.RewardType.XP)
	assert_eq(DailyStreakSchedule.reward_for(3).type, DailyStreakSchedule.RewardType.GEM)
	assert_eq(DailyStreakSchedule.reward_for(4).type, DailyStreakSchedule.RewardType.GOLD)

func test_escalation_amounts():
	# Pin enough points to lock the curve.
	assert_eq(DailyStreakSchedule.reward_for(7).type, DailyStreakSchedule.RewardType.GOLD)
	assert_eq(DailyStreakSchedule.reward_for(7).amount, 100)
	assert_eq(DailyStreakSchedule.reward_for(5).type, DailyStreakSchedule.RewardType.XP)
	assert_eq(DailyStreakSchedule.reward_for(5).amount, 40)
	assert_eq(DailyStreakSchedule.reward_for(9).type, DailyStreakSchedule.RewardType.GEM)
	assert_eq(DailyStreakSchedule.reward_for(9).amount, 11)

func test_day_thirty_is_gem_jackpot():
	var r := DailyStreakSchedule.reward_for(30)
	assert_eq(r.type, DailyStreakSchedule.RewardType.GEM)
	# Jackpot override — NOT the +3 progression value (which would be 32).
	assert_eq(r.amount, 250)

func test_out_of_range_days_are_safe():
	# Clamp policy: <=0 → day 1, >30 → day 30. No crash.
	var low := DailyStreakSchedule.reward_for(0)
	assert_eq(low.type, DailyStreakSchedule.RewardType.GOLD)
	assert_eq(low.amount, 50)
	var high := DailyStreakSchedule.reward_for(31)
	assert_eq(high.type, DailyStreakSchedule.RewardType.GEM)
	assert_eq(high.amount, 250)
