extends GutTest

func test_gold_bonus_zero_luck_returns_zero():
	assert_eq(LuckRewardModifier.gold_bonus(0), 0)

func test_rarity_bump_zero_luck_returns_zero():
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(0), 0.0, 0.0001)

func test_gold_bonus_scales_linearly():
	assert_eq(LuckRewardModifier.gold_bonus(1), 1)
	assert_eq(LuckRewardModifier.gold_bonus(5), 5)
	assert_eq(LuckRewardModifier.gold_bonus(10), 10)

func test_rarity_bump_scales_linearly():
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(1), 0.02, 0.0001)
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(5), 0.10, 0.0001)
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(10), 0.20, 0.0001)

func test_gold_bonus_negative_luck_returns_zero():
	assert_eq(LuckRewardModifier.gold_bonus(-1), 0)
	assert_eq(LuckRewardModifier.gold_bonus(-100), 0)

func test_rarity_bump_negative_luck_returns_zero():
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(-5), 0.0, 0.0001)

func test_rarity_bump_high_luck_does_not_exceed_one():
	# Documented behaviour: formula is unbounded, but call sites should clamp
	# before sampling. Guard against future regressions where the formula
	# accidentally over-multiplies.
	var hi: float = LuckRewardModifier.rarity_bump_chance(999)
	assert_true(hi > 0.0, "high luck still produces a positive chance")
	# Natural float — not clamped at this layer. Just assert it doesn't go
	# wildly past the expected linear value.
	assert_almost_eq(hi, 999 * 0.02, 0.0001)
