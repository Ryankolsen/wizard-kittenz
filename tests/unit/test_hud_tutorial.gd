extends GutTest

# movement_attack tutorial auto-trigger wiring (issue #604, PRD #596). Mirrors
# the main_menu wiring tests in test_character_creation.gd (issue #603).
#
# is_touch_platform() is a real OS.has_feature check with no test seam, so
# the touch-gated assertion follows the same guard already established in
# test_touch_controls.gd's test_hud_hides_potion_belt_on_touch_platform: skip
# via pending() on a non-touch CI/dev rig instead of asserting a platform
# fact we can't control from here.

func _find_tutorial_overlay(scene: Node) -> Node:
	return scene.find_child("TutorialOverlay", true, false)

func test_hud_triggers_movement_attack_on_touch():
	if not TouchControls.is_touch_platform():
		pending("movement_attack auto-trigger is touch-only")
		return
	GameState.tutorial_seen_topics = []
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := _find_tutorial_overlay(hud)
	assert_not_null(overlay, "a fresh install on a touch platform must auto-show the movement_attack overlay")
	assert_true(overlay.visible, "the overlay must be open, not just instantiated")
	get_tree().paused = false

func test_hud_does_not_trigger_movement_attack_on_desktop():
	# On a non-touch platform (the normal desktop test rig), is_touch_platform()
	# is false, so TutorialTrigger.should_trigger must refuse this touch_only
	# topic regardless of tutorial_seen_topics.
	if TouchControls.is_touch_platform():
		pending("this asserts the desktop (non-touch) branch")
		return
	GameState.tutorial_seen_topics = []
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_null(_find_tutorial_overlay(hud),
		"desktop must not auto-show the touch-only movement_attack overlay")

func test_movement_attack_marked_seen_persists_across_hud_reload():
	if not TouchControls.is_touch_platform():
		pending("movement_attack auto-trigger is touch-only")
		return
	GameState.tutorial_seen_topics = []
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := _find_tutorial_overlay(hud)
	assert_not_null(overlay)
	overlay.finished.emit("movement_attack")
	get_tree().paused = false
	assert_true(GameState.tutorial_seen_topics.has("movement_attack"),
		"finishing the overlay must mark movement_attack seen")

	var hud_b = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud_b)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_null(_find_tutorial_overlay(hud_b),
		"once seen, a fresh HUD load must not re-trigger the tutorial")
