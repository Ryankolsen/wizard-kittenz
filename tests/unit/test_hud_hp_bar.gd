extends GutTest

# Tests for the HUD HP bar fill-ratio math + scaled-label render. Drives
# HUD.hp_bar_ratio / HUD.hp_bar_label directly so the "bar fills against
# the active (real OR effective_stats) HP pool" invariant is exercised
# without a SceneTree.
#
# Sibling to test_hud_xp_bar.gd: where xp_bar_label closed #18 AC#4 by
# wiring the scaled "Lv.10 (Lv.3)" label, hp_bar_label closes the HP
# routing display gap noted in a591f9e — once CoopRouter wires up
# at the call site, damage will route to effective_stats.hp; the HUD must
# read from the same place or the bar will visibly desync from the actual
# fighting HP.

# --- hp_bar_ratio ------------------------------------------------------------

func test_hp_bar_ratio_full_hp_is_one():
	assert_eq(HUD.hp_bar_ratio(10, 10), 1.0)

func test_hp_bar_ratio_half_hp_is_half():
	assert_eq(HUD.hp_bar_ratio(5, 10), 0.5)

func test_hp_bar_ratio_zero_hp_is_zero():
	assert_eq(HUD.hp_bar_ratio(0, 10), 0.0)

func test_hp_bar_ratio_negative_hp_clamps_to_zero():
	# Defensive: take_damage caps at hp so negative shouldn't happen,
	# but a single-frame race that drove hp below zero must not invert
	# the bar.
	assert_eq(HUD.hp_bar_ratio(-5, 10), 0.0)

func test_hp_bar_ratio_overflow_clamps_to_one():
	# Defensive: heal caps at max_hp so hp > max_hp shouldn't happen,
	# but a transient state during scaling teardown (effective_max
	# shrinks before effective_hp gets re-clamped) must not blow the
	# bar past full.
	assert_eq(HUD.hp_bar_ratio(15, 10), 1.0)

func test_hp_bar_ratio_zero_max_is_zero():
	# Uninitialized CharacterData has max_hp == 0; bar reads empty
	# rather than dividing by zero.
	assert_eq(HUD.hp_bar_ratio(0, 0), 0.0)
	assert_eq(HUD.hp_bar_ratio(5, 0), 0.0)

func test_hp_bar_ratio_solo_default_sentinel():
	# Default args (effective_hp == -1, effective_max == -1) is the
	# "no scaling" sentinel; ratio falls through to real hp/max_hp.
	assert_eq(HUD.hp_bar_ratio(8, 10, -1, -1), 0.8)

func test_hp_bar_ratio_uses_effective_when_provided():
	# L10 player in L3 party: real_stats has max_hp ~26, but the local
	# member's effective_stats has max_hp 10. Bar fills against effective.
	# Real shows 26/26 (full) but effective shows 5/10 (half-hurt) — the
	# ratio MUST reflect effective so the player sees they're hurt.
	assert_almost_eq(HUD.hp_bar_ratio(26, 26, 5, 10), 0.5, 0.0001)

func test_hp_bar_ratio_falls_through_when_effective_max_zero():
	# Defensive: a stale {hp: 0, max_hp: 0} from a half-built PartyMember
	# (effective_stats.max_hp == 0 should never happen; from_character
	# always clones a populated CharacterData) must NOT render the bar
	# as 0% empty. Falls back to real ratio.
	assert_eq(HUD.hp_bar_ratio(8, 10, 0, 0), 0.8)

func test_hp_bar_ratio_falls_through_when_effective_hp_negative():
	# Defensive: -1 sentinel on hp alone (with a populated max) falls
	# through to real. Pinned so a future helper that mistakenly returns
	# {-1, 10} doesn't render "HP -1/10" garbage.
	assert_eq(HUD.hp_bar_ratio(8, 10, -1, 10), 0.8)

func test_hp_bar_ratio_effective_zero_hp_is_zero():
	# Player at zero effective HP (took fatal damage in scaled co-op)
	# reads as empty bar. Real_stats might still be full but the
	# effective view IS the dying view.
	assert_eq(HUD.hp_bar_ratio(26, 26, 0, 10), 0.0)

func test_hp_bar_ratio_floor_player_uses_real_when_effective_matches():
	# Floor player: effective_stats == clone of real_stats, so the
	# values match. Either branch picks the same ratio.
	assert_eq(HUD.hp_bar_ratio(8, 10, 8, 10), 0.8)

# --- hp_bar_label ------------------------------------------------------------

func test_hp_bar_label_solo_default_sentinel():
	# Default args (effective_hp == -1, effective_max == -1) is the
	# "no scaling" sentinel; existing solo callers omit the args and
	# get the standard "HP X/Y" render.
	assert_eq(HUD.hp_bar_label(10, 10), "HP 10/10")

func test_hp_bar_label_solo_explicit_sentinels_match_default():
	# Explicit -1/-1 == default; no behavioral split between "passed"
	# and "omitted". Pinned so the future caller that always passes
	# the helper's return value (-1/-1 for solo, populated for co-op)
	# inherits the existing solo behavior on every fall-through path.
	assert_eq(HUD.hp_bar_label(8, 10, -1, -1), "HP 8/10")

func test_hp_bar_label_scaled_session_uses_effective():
	# L10 player in L3 party: real has hp/max_hp ~26/26, effective has
	# 5/10 (half the scaled pool). Label shows the effective view —
	# the actual fighting HP. The XP bar's "Lv.10 (Lv.3)" already
	# signals scaling so the HP bar doesn't repeat that.
	assert_eq(HUD.hp_bar_label(26, 26, 5, 10), "HP 5/10")

func test_hp_bar_label_floor_player_renders_normal():
	# Floor player: effective == clone of real; values match. Either
	# branch fires (effective is provided, so the effective branch
	# fires) but the rendered text is identical to the solo path —
	# no spurious "different" rendering for the floor player.
	assert_eq(HUD.hp_bar_label(8, 10, 8, 10), "HP 8/10")

func test_hp_bar_label_at_zero_hp():
	# Player just died: HP reads 0. Same shape solo and scaled.
	assert_eq(HUD.hp_bar_label(0, 10), "HP 0/10")
	assert_eq(HUD.hp_bar_label(26, 26, 0, 10), "HP 0/10")

func test_hp_bar_label_zero_effective_max_falls_through_to_real():
	# Defensive: a stale {hp: 0, max_hp: 0} from a half-built
	# PartyMember (shouldn't happen — from_character always clones a
	# populated CharacterData) must NOT render "HP 0/0" garbage when
	# real_stats has valid values. Falls back to real.
	assert_eq(HUD.hp_bar_label(8, 10, 0, 0), "HP 8/10")

func test_hp_bar_label_negative_effective_hp_falls_through_to_real():
	# Defensive: a stale {-1, 10} from a partial helper return falls
	# back to real. Pinned so a future bug where the helper returns
	# {-1, populated_max} doesn't render "HP -1/10".
	assert_eq(HUD.hp_bar_label(8, 10, -1, 10), "HP 8/10")

func test_hp_bar_label_zero_max_renders_safely():
	# Defensive: uninitialized CharacterData has max_hp == 0; format
	# must not crash on division (string interpolation handles zero
	# fine) — pinned so a pre-_ready HUD frame doesn't crash.
	assert_eq(HUD.hp_bar_label(0, 0), "HP 0/0")

func test_hp_bar_label_overflow_renders_raw_values():
	# Defensive: hp > max_hp shouldn't happen but the label shows raw
	# values (no clamping in the string). The bar's RATIO clamps; the
	# label is informational.
	assert_eq(HUD.hp_bar_label(15, 10), "HP 15/10")
