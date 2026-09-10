extends GutTest

func after_each():
	var seq := get_node_or_null("/root/TutorialSequencer")
	if seq != null:
		seq.consume_pending()
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_tutorial_sequencer_autoload_is_registered():
	var seq := get_node_or_null("/root/TutorialSequencer")
	assert_not_null(seq, "TutorialSequencer autoload must be registered in project.godot")

func test_queue_then_consume_returns_topic():
	var seq := get_node("/root/TutorialSequencer")
	seq.queue_topic("tavern")
	assert_eq(seq.consume_pending(), "tavern")

func test_consume_clears_pending():
	var seq := get_node("/root/TutorialSequencer")
	seq.queue_topic("tavern")
	seq.consume_pending()
	assert_eq(seq.consume_pending(), "")

func test_queue_overwrites_prior_pending():
	var seq := get_node("/root/TutorialSequencer")
	seq.queue_topic("a")
	seq.queue_topic("b")
	assert_eq(seq.consume_pending(), "b")

func test_replay_topic_ignores_seen_state():
	var seq := get_node("/root/TutorialSequencer")
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = TutorialProgress.mark_seen(gs.tutorial_seen_topics, "tavern")

	seq.replay_topic("tavern")

	var found_overlay: TutorialOverlay = null
	for child in get_tree().root.get_children():
		if child is TutorialOverlay:
			found_overlay = child
			break
	assert_not_null(found_overlay, "replay_topic should open a TutorialOverlay under the tree root even when seen")
	if found_overlay != null:
		found_overlay.queue_free()

func test_replay_topic_marks_seen_on_finish():
	var seq := get_node("/root/TutorialSequencer")
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = []

	seq.replay_topic("tavern")

	var found_overlay: TutorialOverlay = null
	for child in get_tree().root.get_children():
		if child is TutorialOverlay:
			found_overlay = child
			break
	assert_not_null(found_overlay, "expected an overlay to have been added")
	if found_overlay != null:
		found_overlay.skip()
		assert_true(gs.tutorial_seen_topics.has("tavern"), "topic should be marked seen after finish")
