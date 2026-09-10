extends GutTest

# Pure should_trigger decision predicate for the tutorial/help overlay
# (#600, PRD #596). Every scene's _ready consults this to decide whether to
# auto-show a topic right now. No node lookups, no persistence writes --
# those are the caller's job once the overlay closes.

func test_should_trigger_true_for_unseen_universal_topic():
	assert_true(TutorialTrigger.should_trigger("pause_menu", [], false))

func test_should_trigger_false_when_already_seen():
	assert_false(TutorialTrigger.should_trigger("pause_menu", ["pause_menu"], false))

func test_touch_only_topic_fires_on_touch():
	assert_true(TutorialTrigger.should_trigger("movement_attack", [], true))

func test_touch_only_topic_skips_on_desktop():
	assert_false(TutorialTrigger.should_trigger("movement_attack", [], false))

func test_unknown_topic_never_triggers():
	assert_false(TutorialTrigger.should_trigger("not_a_real_topic", [], false))
