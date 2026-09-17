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

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

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

# achievements tutorial auto-trigger wiring (issue #608, PRD #596). The badge
# becomes visible the first frame an achievement unlocks (AchievementBadge.
# should_show flips false->true); that transition is the edge that fires the
# tutorial, mirroring _check_player_dead's alive->dead edge-trigger comment.

func test_achievement_badge_becoming_visible_triggers_tutorial():
	GameState.tutorial_seen_topics = []
	GameState.achievement_service.account.achievement_state["first_kill"] = {
		"unlocked_at": 0, "claimed": false, "earned_by_slot": "",
	}
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var overlay := _find_tutorial_overlay(hud)
	assert_not_null(overlay, "an unlocked, unclaimed achievement must auto-show the achievements overlay")
	assert_true(overlay.visible, "the overlay must be open, not just instantiated")
	assert_false(get_tree().paused,
		"the achievements overlay must not pause the tree — it can trigger mid-combat")

func test_achievement_badge_in_tutorial_group():
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var badge: Node = hud.find_child("AchievementBadge", true, false)
	assert_not_null(badge, "hud.tscn must contain a node named AchievementBadge")
	assert_true(badge.is_in_group("tutorial_target_achievement_badge"),
		"AchievementBadge must be in the tutorial_target_achievement_badge group")

func test_badge_staying_visible_does_not_retrigger():
	GameState.tutorial_seen_topics = []
	GameState.achievement_service.account.achievement_state["first_kill"] = {
		"unlocked_at": 0, "claimed": false, "earned_by_slot": "",
	}
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	hud._update_achievement_badge()
	hud._update_achievement_badge()
	var overlays: Array = hud.find_children("TutorialOverlay", "", true, false)
	assert_eq(overlays.size(), 1,
		"the badge staying visible across polls must not re-instantiate the overlay")

func test_already_seen_achievements_does_not_retrigger():
	GameState.tutorial_seen_topics = ["achievements"]
	GameState.achievement_service.account.achievement_state["first_kill"] = {
		"unlocked_at": 0, "claimed": false, "earned_by_slot": "",
	}
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_null(_find_tutorial_overlay(hud),
		"an already-seen achievements topic must not re-trigger on the badge's visibility edge")

# pause_menu tutorial auto-trigger removal (issue #617, PRD #614). The
# pause-button tip no longer auto-fires from HUD at all -- the achievements
# tutorial's chained hop into pause_menu, and the fallback timer, were both
# removed. The pause_menu topic itself is untouched and still replayable via
# the Help menu (TutorialSequencer.replay_topic("pause_menu")); a future
# slice (#618) introduces a new level_up-triggered auto-show.

func test_achievements_finished_does_not_chain_into_any_further_tutorial():
	GameState.tutorial_seen_topics = []
	GameState.achievement_service.account.achievement_state["first_kill"] = {
		"unlocked_at": 0, "claimed": false, "earned_by_slot": "",
	}
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var achievements_overlay := _find_tutorial_overlay(hud)
	assert_not_null(achievements_overlay)
	var before: int = hud.find_children("TutorialOverlay", "", true, false).size()
	achievements_overlay.finished.emit("achievements")
	assert_true(GameState.tutorial_seen_topics.has("achievements"),
		"finishing the achievements overlay must still mark achievements seen")
	var after: int = hud.find_children("TutorialOverlay", "", true, false).size()
	assert_eq(after, before,
		"finishing the achievements overlay must not chain into any further tutorial overlay")

func test_hud_no_longer_has_pause_menu_fallback_wiring():
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	assert_false(hud.has_method("_maybe_show_pause_menu_tutorial"),
		"the removed fallback trigger method must no longer exist on HUD")
	assert_true(hud.find_children("Timer", "", true, false).is_empty(),
		"a fresh HUD must not create the removed pause_menu fallback Timer")
