extends GutTest

# Pure-function tests for CastProgressBar.fill_width/format_remaining — the
# floating cast-progress bar shown above the player while any channeled
# spell (cast_time > 0) is casting. View glue (parenting above the player,
# follow-the-player, show/hide on channel state) has no automated coverage,
# same test-style split as test_enemy_health_bar.gd.

func test_zero_progress_renders_empty_bar():
	assert_almost_eq(CastProgressBar.fill_width(0.0, 40.0), 0.0, 0.0001)

func test_half_progress_fills_half_bar_width():
	assert_almost_eq(CastProgressBar.fill_width(0.5, 40.0), 20.0, 0.0001)

func test_full_progress_fills_full_bar_width():
	assert_almost_eq(CastProgressBar.fill_width(1.0, 40.0), 40.0, 0.0001)

func test_progress_over_one_clamps_to_full_width():
	assert_almost_eq(CastProgressBar.fill_width(1.5, 40.0), 40.0, 0.0001)

func test_negative_progress_clamps_to_empty_bar():
	assert_almost_eq(CastProgressBar.fill_width(-0.2, 40.0), 0.0, 0.0001)

# --- countdown label ---------------------------------------------------

func test_format_remaining_renders_one_decimal_and_unit():
	assert_eq(CastProgressBar.format_remaining(12.34), "12.3s")

func test_format_remaining_zero():
	assert_eq(CastProgressBar.format_remaining(0.0), "0.0s")
