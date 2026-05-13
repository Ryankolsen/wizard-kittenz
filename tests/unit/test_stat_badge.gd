extends GutTest

# Unspent stat points badge predicate (#58, PRD #52). Pure-function tests
# for the visibility rule shared by the HUD badge and the pause-menu
# Stats tab badge. The helper is a static so it can be exercised without
# spinning up the HUD / PauseMenu scene tree.

func test_should_show_true_for_positive_points():
	assert_true(StatBadge.should_show(1))
	assert_true(StatBadge.should_show(99))

func test_should_show_false_at_zero():
	assert_false(StatBadge.should_show(0))

func test_should_show_false_for_negative():
	# Defensive: a stale save dict or half-built CharacterData should not
	# render a phantom badge. Negative is treated identically to zero.
	assert_false(StatBadge.should_show(-1))
	assert_false(StatBadge.should_show(-100))
