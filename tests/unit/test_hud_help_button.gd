extends GutTest

# HelpButton wiring (issue #611, PRD #596). hud.tscn's HelpButton opens the
# already-landed TutorialTopicMenu (#610); picking a topic calls
# TutorialSequencer.replay_topic(topic_id) (#602) and closes the menu.
#
# test_topic_selected_calls_replay_topic mirrors test_tutorial_sequencer.gd's
# own verification style (no mock seam exists on the TutorialSequencer
# autoload, so the established pattern is to call the real autoload and
# observe its effect: a TutorialOverlay appears under get_tree().root).

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()
	# Clean up any TutorialOverlay left under the tree root by replay_topic.
	for child in get_tree().root.get_children():
		if child is TutorialOverlay:
			child.queue_free()

func test_help_button_opens_topic_menu():
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var help_btn := hud.find_child("HelpButton", true, false) as Button
	assert_not_null(help_btn, "HUD must have a HelpButton")
	help_btn.pressed.emit()
	var menu: Node = hud.find_child("TutorialTopicMenu", true, false)
	assert_not_null(menu, "pressing HelpButton must instantiate TutorialTopicMenu as a child")

func test_topic_selected_calls_replay_topic():
	GameState.tutorial_seen_topics = []
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var help_btn := hud.find_child("HelpButton", true, false) as Button
	help_btn.pressed.emit()
	var menu = hud.find_child("TutorialTopicMenu", true, false)
	assert_not_null(menu, "menu must exist before emitting topic_selected")
	menu.topic_selected.emit("tavern")
	await get_tree().process_frame

	var found_overlay: TutorialOverlay = null
	for child in get_tree().root.get_children():
		if child is TutorialOverlay:
			found_overlay = child
			break
	assert_not_null(found_overlay,
		"picking a topic must call TutorialSequencer.replay_topic, which opens a TutorialOverlay under the tree root")

	var menu_after: Node = hud.find_child("TutorialTopicMenu", true, false)
	assert_null(menu_after, "the topic menu must free itself after a topic is picked")

	if found_overlay != null:
		found_overlay.skip()
	get_tree().paused = false

func test_closing_menu_without_picking_does_not_call_replay_topic():
	# Identity-based rather than count-based: TutorialOverlay.skip()/close()
	# hide the overlay but don't free it (see tutorial_overlay.gd), so a
	# prior test's overlay can still be a pending-queue_free root child when
	# this test starts. Comparing instance ids (not counts) isolates
	# whether *this* action added a new one.
	var overlay_ids_before := {}
	for child in get_tree().root.get_children():
		if child is TutorialOverlay:
			overlay_ids_before[child.get_instance_id()] = true

	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var help_btn := hud.find_child("HelpButton", true, false) as Button
	help_btn.pressed.emit()
	var menu = hud.find_child("TutorialTopicMenu", true, false)
	assert_not_null(menu)
	menu.closed.emit()
	await get_tree().process_frame

	var new_overlay: TutorialOverlay = null
	for child in get_tree().root.get_children():
		if child is TutorialOverlay and not overlay_ids_before.has(child.get_instance_id()):
			new_overlay = child
			break
	assert_null(new_overlay,
		"closing without picking a topic must not call replay_topic (no new TutorialOverlay)")

	var menu_after: Node = hud.find_child("TutorialTopicMenu", true, false)
	assert_null(menu_after, "the topic menu must free itself on close")

func test_help_button_hidden_on_touch():
	if not TouchControls.is_touch_platform():
		pending("HelpButton hide-on-touch only asserts on a touch platform")
		return
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var help_btn := hud.find_child("HelpButton", true, false) as Button
	assert_not_null(help_btn)
	assert_false(help_btn.visible, "HUD's HelpButton must be hidden on touch platforms")

func test_help_button_visible_on_desktop():
	if TouchControls.is_touch_platform():
		pending("this asserts the desktop (non-touch) branch")
		return
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var help_btn := hud.find_child("HelpButton", true, false) as Button
	assert_not_null(help_btn)
	assert_true(help_btn.visible, "HUD's HelpButton must be visible on desktop")
