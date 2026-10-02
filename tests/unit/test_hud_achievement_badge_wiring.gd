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
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge: Control = scene.find_child("AchievementBadge", true, false)
	var button: Button = scene.find_child("PauseButton", true, false)
	assert_not_null(badge, "hud.tscn must contain a node named AchievementBadge")
	assert_true(badge is NotificationDot, "AchievementBadge must now be a NotificationDot")
	assert_eq(badge.get_parent().name, "PauseButton",
		"AchievementBadge must stay a child of PauseButton")
	# Issue #635: the dot is anchored to the button's horizontal center
	# (anchor_left == anchor_right == 0.5) and positioned at runtime from the
	# button's own rendered text width, rather than a hardcoded pixel offset
	# that assumed a fixed button width.
	assert_eq(badge.anchor_left, 0.5, "AchievementBadge must anchor to the button's horizontal center")
	assert_eq(badge.anchor_right, 0.5, "AchievementBadge must anchor to the button's horizontal center")
	var expected_half_width := _text_half_width(button)
	assert_almost_eq(badge.offset_left, expected_half_width + 4.0, 0.5,
		"the dot's left edge must sit just past the button text's half-width + gap")
	var expected_dot_width: float = badge.custom_minimum_size.x
	assert_almost_eq(badge.offset_right - badge.offset_left, expected_dot_width, 0.5,
		"the dot's width must be preserved by the runtime offset_right computation")
	assert_eq(badge.offset_top, -6.0)
	assert_eq(badge.offset_bottom, 10.0)
	assert_false(badge.visible, "AchievementBadge must start hidden")

# Mirrors hud.gd's _position_dot_after_text's own font measurement, so this
# test exercises the dynamic computation rather than re-asserting a literal.
func _text_half_width(button: Button) -> float:
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	if font == null:
		return 0.0
	return font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2.0

func test_position_dot_after_text_tracks_button_text_width():
	var scene = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge: Control = scene.find_child("AchievementBadge", true, false)
	var button: Button = scene.find_child("PauseButton", true, false)
	button.text = "P"
	scene.call("_position_dot_after_text", badge, button)
	var short_text_offset: float = badge.offset_left
	button.text = "Pause For Everyone And More"
	scene.call("_position_dot_after_text", badge, button)
	var long_text_offset: float = badge.offset_left
	assert_gt(long_text_offset, short_text_offset,
		"offset_left must grow with the button's own rendered text width, not stay fixed")

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
