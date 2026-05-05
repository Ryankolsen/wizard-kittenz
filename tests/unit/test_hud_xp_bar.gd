extends GutTest

# Tests for the HUD XP bar fill-ratio math. Drives HUD.xp_bar_ratio
# directly so the "bar fills proportionally and resets on level-up"
# invariant is exercised without a SceneTree. The post-level-up reset
# falls out for free because ProgressionSystem.add_xp decrements
# c.xp by the threshold, so the next ratio call sees the carry-over
# remainder against the new (higher) level's threshold.

func test_ratio_zero_xp_at_level_one_is_zero():
	assert_eq(HUD.xp_bar_ratio(1, 0), 0.0)

func test_ratio_half_threshold_is_half():
	# L1 threshold = 5; xp=2 is 0.4, xp=3 is 0.6 — pick the exact midpoint
	# at L2 (threshold 10) for a clean assert without floating drift.
	assert_almost_eq(HUD.xp_bar_ratio(2, 5), 0.5, 0.0001)

func test_ratio_at_threshold_clamps_to_one():
	# xp == threshold means "level-up about to fire on the next add_xp."
	# Bar reads as full; ratio is exactly 1.0.
	assert_eq(HUD.xp_bar_ratio(1, 5), 1.0)

func test_ratio_clamps_to_one_when_xp_exceeds_threshold():
	# Defensive: shouldn't happen in normal flow (add_xp resolves the
	# overflow into a level-up + remainder), but a single-frame race
	# where xp > threshold mustn't blow the bar past full.
	assert_eq(HUD.xp_bar_ratio(1, 999), 1.0)

func test_ratio_clamps_to_zero_for_negative_xp():
	# Defensive: xp shouldn't go negative (add_xp rejects negatives),
	# but the bar must not invert.
	assert_eq(HUD.xp_bar_ratio(1, -5), 0.0)

func test_ratio_resets_after_level_up():
	# The acceptance criterion: "XP bar fills and resets on level-up."
	# Drive it through ProgressionSystem so the fill ratio reflects the
	# actual game flow, not just static math.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	# Right before threshold: bar reads 4/5 = 0.8.
	ProgressionSystem.add_xp(c, 4)
	assert_eq(c.level, 1)
	assert_almost_eq(HUD.xp_bar_ratio(c.level, c.xp), 0.8, 0.0001)
	# Cross the threshold: leveled up, xp resets to remainder, bar
	# falls back to a small fraction of the new (larger) threshold.
	ProgressionSystem.add_xp(c, 1)
	assert_eq(c.level, 2)
	assert_eq(c.xp, 0)
	assert_eq(HUD.xp_bar_ratio(c.level, c.xp), 0.0,
		"bar resets to 0 immediately after leveling up at exact threshold")

func test_ratio_carries_remainder_into_new_level():
	# Overshoot: 7 xp at L1 -> level-up + 2 remainder against L2 threshold (10).
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	ProgressionSystem.add_xp(c, 7)
	assert_eq(c.level, 2)
	assert_eq(c.xp, 2)
	assert_almost_eq(HUD.xp_bar_ratio(c.level, c.xp), 0.2, 0.0001,
		"remainder shows as 2/10 of the new level's bar")

func test_ratio_higher_levels_use_higher_thresholds():
	# Curve is linear (5, 10, 15, ...); the same xp value reads as a
	# smaller ratio at higher levels, confirming the threshold is
	# being looked up per-level rather than constant.
	var r2 := HUD.xp_bar_ratio(2, 5)   # 5/10 = 0.5
	var r3 := HUD.xp_bar_ratio(3, 5)   # 5/15 ~= 0.333
	assert_gt(r2, r3, "same xp reads smaller at higher levels")
