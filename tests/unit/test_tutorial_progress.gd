extends GutTest

# Pure seen/mark_seen tracking for the tutorial/help overlay (#598, PRD #596).
# TutorialProgress has no persistence, scene tree, or catalog dependency —
# it operates on a plain Array of topic-id strings passed in by the caller.

func test_is_seen_false_when_absent():
	assert_false(TutorialProgress.is_seen([], "pause_menu"))

func test_mark_seen_adds_new_id():
	assert_eq(TutorialProgress.mark_seen([], "pause_menu"), ["pause_menu"])

func test_is_seen_true_when_present():
	assert_true(TutorialProgress.is_seen(["pause_menu"], "pause_menu"))

func test_mark_seen_is_idempotent():
	assert_eq(TutorialProgress.mark_seen(["pause_menu"], "pause_menu"), ["pause_menu"])

func test_mark_seen_preserves_existing_ids():
	assert_eq(TutorialProgress.mark_seen(["pause_menu"], "tavern"), ["pause_menu", "tavern"])

func test_mark_seen_does_not_mutate_input():
	var original := ["pause_menu"]
	TutorialProgress.mark_seen(original, "tavern")
	assert_eq(original.size(), 1)
	assert_eq(original, ["pause_menu"])

func test_empty_topic_id_ignored():
	var seen_ids := ["pause_menu"]
	assert_false(TutorialProgress.is_seen(seen_ids, ""))
	assert_eq(TutorialProgress.mark_seen(seen_ids, ""), ["pause_menu"])
