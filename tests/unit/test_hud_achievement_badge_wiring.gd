extends GutTest

# Scene-level wiring tests for the HUD's pause-button achievement dot, now
# migrated onto NotificationDot (#625, PRD #620). Mirrors
# test_stat_badge_wiring.gd's shape: pin the node's identity/position, then
# drive GameState.achievement_service to confirm the bound predicate tracks
# AchievementBadge.should_show just like the old hud.gd-driven polling did.

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_achievement_badge_is_a_notification_dot_at_the_same_position():
	var scene = load("res://scenes/hud.tscn").instantiate()
	var badge: Control = scene.find_child("AchievementBadge", true, false)
	assert_not_null(badge, "hud.tscn must contain a node named AchievementBadge")
	assert_true(badge is NotificationDot, "AchievementBadge must now be a NotificationDot")
	assert_eq(badge.get_parent().name, "PauseButton",
		"AchievementBadge must stay a child of PauseButton")
	assert_eq(badge.offset_left, 52.0)
	assert_eq(badge.offset_top, -6.0)
	assert_eq(badge.offset_right, 66.0)
	assert_eq(badge.offset_bottom, 10.0)
	assert_false(badge.visible, "AchievementBadge must start hidden")
	scene.free()

func test_achievement_badge_visible_with_an_unclaimed_achievement():
	var gs := get_node("/root/GameState")
	gs.achievement_service.account.achievement_state = {
		"some_id": {"claimed": false},
	}
	var scene = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge: Control = scene.find_child("AchievementBadge", true, false)
	assert_true(badge.visible, "an unlocked, unclaimed achievement must show the dot")

func test_achievement_badge_hidden_when_all_claimed():
	var gs := get_node("/root/GameState")
	gs.achievement_service.account.achievement_state = {
		"some_id": {"claimed": true},
	}
	var scene = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge: Control = scene.find_child("AchievementBadge", true, false)
	assert_false(badge.visible, "an all-claimed achievement_state must hide the dot")

func test_achievement_badge_hidden_when_achievement_service_unavailable():
	var gs := get_node("/root/GameState")
	gs.achievement_service = null
	var scene = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge: Control = scene.find_child("AchievementBadge", true, false)
	assert_false(badge.visible,
		"a missing achievement_service must keep the dot hidden, not crash")

func test_achievement_badge_updates_live_when_claimed():
	var gs := get_node("/root/GameState")
	gs.achievement_service.account.achievement_state = {
		"some_id": {"claimed": false},
	}
	var scene = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge: Control = scene.find_child("AchievementBadge", true, false)
	assert_true(badge.visible, "must start visible while unclaimed")
	gs.achievement_service.account.achievement_state["some_id"]["claimed"] = true
	await get_tree().process_frame
	assert_false(badge.visible,
		"the self-polling dot must hide within one frame of the claim")
