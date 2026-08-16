extends GutTest

# Pure-function tests for HoomanHealthBar.fill_width — the bar's per-frame
# Fill ColorRect width math. Mirrors test_enemy_health_bar.gd's split: view
# glue (parenting above the hooman, following hp each frame) is exercised
# indirectly via test_hooman.gd's node-level tests.

func test_full_hp_fills_full_bar_width():
	assert_almost_eq(HoomanHealthBar.fill_width(10, 10, 32.0), 32.0, 0.0001)

func test_health_bar_fill_width_matches_hp_ratio():
	assert_almost_eq(HoomanHealthBar.fill_width(5, 10, 32.0), 16.0, 0.0001)

func test_zero_hp_renders_empty_bar():
	assert_almost_eq(HoomanHealthBar.fill_width(0, 10, 32.0), 0.0, 0.0001)

func test_zero_max_hp_returns_zero_width():
	assert_almost_eq(HoomanHealthBar.fill_width(4, 0, 32.0), 0.0, 0.0001)
