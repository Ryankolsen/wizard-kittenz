extends GutTest

# Walking skeleton for TutorialOverlay (#601, parent PRD #596). Generic,
# data-driven step renderer over TutorialCatalog.steps_for — these tests
# pin the open/advance/skip/finish contract and the highlight-vs-text-only
# fallback. No TutorialProgress / TutorialTrigger wiring here (later slice).

func after_each():
	# Defensive — a failing open() could leave the tree paused and poison
	# every subsequent test that polls _process, mirroring test_pause_menu.gd.
	get_tree().paused = false

func test_overlay_scene_has_required_nodes():
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	var close_btn = scene.find_child("CloseButton", true, false)
	var skip_btn = scene.find_child("SkipButton", true, false)
	var label = scene.find_child("StepLabel", true, false)
	assert_not_null(close_btn, "tutorial_overlay.tscn must have a close (X) button")
	assert_not_null(skip_btn, "tutorial_overlay.tscn must have a Skip button")
	assert_not_null(label, "tutorial_overlay.tscn must have a StepLabel")
	scene.free()

func test_overlay_process_mode_is_always():
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	assert_eq(scene.process_mode, Node.PROCESS_MODE_ALWAYS,
		"TutorialOverlay must process while tree is paused")
	scene.free()

func test_open_pauses_tree_and_shows_first_step():
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("pause_menu")
	assert_true(get_tree().paused, "open() must pause the scene tree")
	var label = scene.find_child("StepLabel", true, false) as Label
	var steps = TutorialCatalog.steps_for("pause_menu")
	assert_eq(label.text, steps[0]["text"], "open() must show the first step's text")
	get_tree().paused = false

func test_advance_shows_next_step_text():
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("pause_menu")
	scene.advance()
	var label = scene.find_child("StepLabel", true, false) as Label
	var steps = TutorialCatalog.steps_for("pause_menu")
	assert_eq(label.text, steps[1]["text"], "advance() must show step index 1's text")
	get_tree().paused = false

func test_advance_past_last_step_emits_finished():
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	add_child_autofree(scene)
	watch_signals(scene)
	scene.open("pause_menu")
	var steps = TutorialCatalog.steps_for("pause_menu")
	for i in range(steps.size()):
		scene.advance()
	assert_signal_emitted(scene, "finished", "advancing past the last step must emit finished")
	assert_false(get_tree().paused, "finishing the topic must unpause the tree")

func test_skip_emits_finished_from_any_step():
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	add_child_autofree(scene)
	watch_signals(scene)
	scene.open("pause_menu")
	scene.advance()
	scene.skip()
	assert_signal_emitted(scene, "finished", "skip() must emit finished")
	assert_false(get_tree().paused, "skip() must unpause the tree")

func test_missing_target_group_renders_text_only():
	# "tavern" step 1 has target_group == "" (no group to resolve at all),
	# which must fall back to the plain centered text bubble without crashing.
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("tavern")
	scene.advance()
	var box = scene.find_child("HighlightBox", true, false) as Control
	assert_false(box.visible, "highlight box must stay hidden when there is no resolvable target")
	get_tree().paused = false

func test_node2d_target_shows_highlight_box_at_projected_position():
	# Issue #609 (QA finding): Bartender is a Node2D, not a Control, so
	# _position_for_target must support projecting a Node2D's world position
	# through the viewport's canvas transform to screen space and drawing the
	# highlight box centered on that projected point.
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	add_child_autofree(scene)
	var target := Node2D.new()
	add_child_autofree(target)
	target.global_position = Vector2(100, 50)
	target.add_to_group("tutorial_target_test_node2d")

	scene._position_for_target("tutorial_target_test_node2d")

	var box := scene.find_child("HighlightBox", true, false) as Control
	assert_true(box.visible, "highlight box must show for a Node2D target")
	var expected: Vector2 = scene.get_viewport().get_canvas_transform() * target.global_position
	var box_center: Vector2 = box.global_position + box.size / 2.0
	assert_almost_eq(box_center.x, expected.x, 1.0,
		"highlight box must be centered on the projected screen position (x)")
	assert_almost_eq(box_center.y, expected.y, 1.0,
		"highlight box must be centered on the projected screen position (y)")


func test_close_unpauses_tree():
	var scene = load("res://scenes/tutorial_overlay.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("pause_menu")
	scene.close()
	assert_false(get_tree().paused, "close() must unpause the scene tree")
