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
	# Compute half-threshold dynamically from the curve so the test stays
	# honest if XP_BASE is retuned.
	var half: int = ProgressionSystem.xp_to_next_level(2) / 2
	var threshold: int = ProgressionSystem.xp_to_next_level(2)
	assert_almost_eq(HUD.xp_bar_ratio(2, half), float(half) / float(threshold), 0.0001)

func test_ratio_at_threshold_clamps_to_one():
	# xp == threshold means "level-up about to fire on the next add_xp."
	# Bar reads as full; ratio is exactly 1.0.
	assert_eq(HUD.xp_bar_ratio(1, ProgressionSystem.xp_to_next_level(1)), 1.0)

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
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var l1: int = ProgressionSystem.xp_to_next_level(1)
	# Right before threshold: bar reads (l1-1)/l1.
	ProgressionSystem.add_xp(c, l1 - 1)
	assert_eq(c.level, 1)
	assert_almost_eq(HUD.xp_bar_ratio(c.level, c.xp), float(l1 - 1) / float(l1), 0.0001)
	# Cross the threshold: leveled up, xp resets to remainder, bar
	# falls back to a small fraction of the new (larger) threshold.
	ProgressionSystem.add_xp(c, 1)
	assert_eq(c.level, 2)
	assert_eq(c.xp, 0)
	assert_eq(HUD.xp_bar_ratio(c.level, c.xp), 0.0,
		"bar resets to 0 immediately after leveling up at exact threshold")

func test_ratio_carries_remainder_into_new_level():
	# Overshoot: (threshold + 2) xp at L1 -> level-up + 2 remainder against L2.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1) + 2)
	assert_eq(c.level, 2)
	assert_eq(c.xp, 2)
	var l2: int = ProgressionSystem.xp_to_next_level(2)
	assert_almost_eq(HUD.xp_bar_ratio(c.level, c.xp), 2.0 / float(l2), 0.0001,
		"remainder shows as 2/threshold of the new level's bar")

func test_ratio_higher_levels_use_higher_thresholds():
	# Curve is monotonically increasing; the same xp value reads as a
	# smaller ratio at higher levels, confirming the threshold is
	# being looked up per-level rather than constant.
	var r2 := HUD.xp_bar_ratio(2, 50)
	var r3 := HUD.xp_bar_ratio(3, 50)
	assert_gt(r2, r3, "same xp reads smaller at higher levels")

# --- xp_bar_label ------------------------------------------------------------
#
# Pure-function label render for the XP bar. Closes #18 AC#4 ("HUD correctly
# shows 'Lv.10 (Lv.3)' format during session"). Drives HUD.xp_bar_label
# directly so the format shape (period after "Lv", parens around effective
# level, em-dash separator, current/threshold) is testable without booting
# the HUD scene tree or constructing a full CoopSession.

func test_xp_bar_label_solo_omits_effective_when_default_sentinel():
	# Default arg (effective_level == -1) is the "no scaling" sentinel —
	# the existing solo HUD wiring passes nothing and gets the un-paren'd
	# label. The render is the existing single-level shape with periods.
	assert_eq(HUD.xp_bar_label(1, 0, 5), "Lv.1 — 0/5")

func test_xp_bar_label_solo_explicit_minus_one_matches_default():
	# Explicit -1 == default -1; no behavioral split between "passed" and
	# "omitted". Locks the sentinel contract for the future caller that
	# computes effective_level via _local_effective_level() and passes -1
	# on every solo / no-session frame.
	assert_eq(HUD.xp_bar_label(10, 5, 50, -1), "Lv.10 — 5/50")

func test_xp_bar_label_scaled_session_renders_real_and_effective():
	# Issue #18 acceptance criterion exact format: a level-10 player in a
	# level-3 party shows "Lv.10 (Lv.3)" with the xp/threshold tail.
	assert_eq(HUD.xp_bar_label(10, 5, 50, 3), "Lv.10 (Lv.3) — 5/50")

func test_xp_bar_label_at_floor_omits_parens():
	# A floor player (real_level == effective_level) is NOT scaled —
	# rendering "Lv.3 (Lv.3)" would be cosmetically wrong (the parens
	# imply scaling). Same single-level branch as the solo path.
	assert_eq(HUD.xp_bar_label(3, 2, 15, 3), "Lv.3 — 2/15")

func test_xp_bar_label_zero_effective_treats_as_no_scaling():
	# Defensive: effective_level == 0 should never happen (PartyScaler
	# floors at 1) but the sentinel-style branch must not render the
	# nonsense "Lv.10 (Lv.0)" if it ever does. <= 0 falls through to
	# the solo render; pinned so a future caller that passes a stale
	# zero from an uninitialized PartyMember doesn't surface garbage.
	assert_eq(HUD.xp_bar_label(10, 5, 50, 0), "Lv.10 — 5/50")

func test_xp_bar_label_scaled_to_level_one_renders_parens():
	# Lowest valid floor (PartyScaler.compute_floor's empty-array default
	# is 1; a single-member party can also have floor == 1). A level-10
	# player in a level-1 floor shows "Lv.10 (Lv.1)" — the parens fire
	# whenever effective < real, all the way down to floor 1.
	assert_eq(HUD.xp_bar_label(10, 0, 50, 1), "Lv.10 (Lv.1) — 0/50")

func test_xp_bar_label_carries_post_levelup_remainder_when_scaled():
	# A scaled L10 player who just leveled to L11 reads as "Lv.11 (Lv.3)"
	# with the post-level-up remainder against the new (L11) threshold.
	# Pins that the prefix logic doesn't depend on the xp/threshold pair.
	assert_eq(HUD.xp_bar_label(11, 2, 55, 3), "Lv.11 (Lv.3) — 2/55")

func test_xp_bar_label_zero_threshold_renders_safely():
	# Defensive: ProgressionSystem.xp_to_next_level should never return 0
	# but a hand-typed cap at max-level might. Format must not crash on
	# division (it's just string interpolation) — pinned so a future
	# "max level reached" path that hands threshold=0 still renders.
	assert_eq(HUD.xp_bar_label(50, 0, 0), "Lv.50 — 0/0")
	assert_eq(HUD.xp_bar_label(50, 0, 0, 3), "Lv.50 (Lv.3) — 0/0")
