extends GutTest

# Pure-function tests for EnemyHealthBar.fill_width — the bar's per-frame
# Fill ColorRect width math. View glue (parenting above the sprite, follow-
# the-enemy, free-on-death, boss exclusion) is verified in the manual QA
# slice #249, mirroring the test-style split in test_hud_xp_bar.gd.

func test_full_hp_fills_full_bar_width():
	assert_almost_eq(EnemyHealthBar.fill_width(4, 4, 32.0), 32.0, 0.0001)

func test_half_hp_fills_half_bar_width():
	assert_almost_eq(EnemyHealthBar.fill_width(2, 4, 32.0), 16.0, 0.0001)

func test_zero_hp_renders_empty_bar():
	assert_almost_eq(EnemyHealthBar.fill_width(0, 4, 32.0), 0.0, 0.0001)

func test_hp_over_max_clamps_to_full_width():
	# Defensive: shouldn't happen post-damage-resolution but a single-frame
	# race that drove hp above max must not extend the fill past the bg.
	assert_almost_eq(EnemyHealthBar.fill_width(5, 4, 32.0), 32.0, 0.0001)

func test_zero_max_hp_returns_zero_width():
	# Divide-by-zero guard inherited from HUD.hp_bar_ratio — an
	# unconfigured enemy (max_hp = 0) renders an empty bar instead of NaN.
	assert_almost_eq(EnemyHealthBar.fill_width(4, 0, 32.0), 0.0, 0.0001)

# --- level label (PRD #376 / issue #377) -----------------------------------

func test_format_level_renders_lv_n():
	assert_eq(EnemyHealthBar.format_level(4), "Lv 4")
