extends GutTest

# Pause-button achievement badge predicate (#450, PRD #446). Pure-function
# tests for the visibility rule, mirroring test_stat_badge.gd's shape —
# the helper is a static so it can be exercised without a scene tree.

func test_should_show_true_for_one_unclaimed():
	assert_true(AchievementBadge.should_show({"a": {"claimed": false}}))

func test_should_show_true_for_mixed_claimed_and_unclaimed():
	assert_true(AchievementBadge.should_show({
		"a": {"claimed": true},
		"b": {"claimed": false},
	}))

func test_should_show_false_for_empty_dict():
	assert_false(AchievementBadge.should_show({}))

func test_should_show_false_when_all_claimed():
	assert_false(AchievementBadge.should_show({
		"a": {"claimed": true},
		"b": {"claimed": true},
	}))
