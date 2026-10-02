extends GutTest

# Scene-level wiring tests for the unspent stat-points badge (#58). The
# pure predicate is covered by test_stat_badge.gd; this file pins that the
# badge nodes exist in the HUD and pause-menu scenes and start hidden, and
# that the pause-menu badge polls live off GameState.current_character.

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_hud_has_stat_points_badge_hidden_by_default():
	var scene = load("res://scenes/hud.tscn").instantiate()
	var badge = scene.find_child("StatPointsBadge", true, false)
	assert_not_null(badge, "hud.tscn must contain a node named StatPointsBadge")
	assert_true(badge is Label, "StatPointsBadge must be a Label")
	assert_false(badge.visible, "StatPointsBadge starts hidden — visibility is driven by skill_points")
	scene.free()

func test_pause_menu_stats_tab_badge_is_notification_dot_child_of_stats_tab_button():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var badge = scene.find_child("StatsTabBadge", true, false)
	assert_not_null(badge, "pause_menu.tscn must contain a node named StatsTabBadge")
	assert_true(badge is NotificationDot, "StatsTabBadge must be a NotificationDot instance")
	assert_not_null(badge.get_parent(), "StatsTabBadge must have a parent")
	assert_eq(badge.get_parent().name, "StatsTabButton", "StatsTabBadge must be a child of StatsTabButton")
	scene.free()

func test_pause_menu_has_stats_tab_badge_hidden_by_default():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var badge = scene.find_child("StatsTabBadge", true, false)
	assert_not_null(badge, "pause_menu.tscn must contain a node named StatsTabBadge")
	assert_false(badge.visible, "StatsTabBadge starts hidden — visibility is driven by skill_points")
	scene.free()

func test_pause_menu_stats_tab_badge_visible_when_points_available():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Pixel")
	c.skill_points = 3
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	# _process drives the badge; tick a frame.
	await get_tree().process_frame
	var badge = scene.find_child("StatsTabBadge", true, false) as NotificationDot
	assert_not_null(badge)
	assert_true(badge.visible, "badge must be visible when skill_points > 0")

func test_pause_menu_stats_tab_badge_hidden_when_no_points():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Pixel")
	c.skill_points = 0
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("StatsTabBadge", true, false) as NotificationDot
	assert_not_null(badge)
	assert_false(badge.visible, "badge must hide when skill_points == 0")

func test_pause_menu_stats_tab_badge_updates_on_change():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Pixel")
	c.skill_points = 0
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("StatsTabBadge", true, false) as NotificationDot
	assert_false(badge.visible)
	c.skill_points = 5
	await get_tree().process_frame
	assert_true(badge.visible, "badge polls per frame — must turn on when points appear")

func test_pause_menu_stats_tab_badge_positioned_past_button_text():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("StatsTabBadge", true, false)
	var button: Button = scene.find_child("StatsTabButton", true, false)
	# Issue #635: the dot is anchored to the button's horizontal center
	# (which always equals the text's own center, since Button text is
	# always centered) and positioned at runtime from the rendered text's
	# half-width, instead of a hardcoded pixel offset that assumed a fixed
	# button width.
	assert_eq(badge.anchor_left, 0.5, "StatsTabBadge must anchor to the button's horizontal center")
	assert_eq(badge.anchor_right, 0.5, "StatsTabBadge must anchor to the button's horizontal center")
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	var half_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2.0
	assert_almost_eq(badge.offset_left, half_width + 4.0, 0.5,
		"the dot's left edge must sit just past the button text's half-width + gap")

func test_pause_menu_stats_tab_badge_offset_tracks_button_text_width():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("StatsTabBadge", true, false)
	var button: Button = scene.find_child("StatsTabButton", true, false)
	button.text = "S"
	scene.call("_position_dot_after_text", badge, button)
	var short_text_offset: float = badge.offset_left
	button.text = "Stats Tab Extra Wide Label"
	scene.call("_position_dot_after_text", badge, button)
	var long_text_offset: float = badge.offset_left
	assert_gt(long_text_offset, short_text_offset,
		"offset_left must grow with the button's own rendered text width, not stay fixed")

func test_pause_menu_stats_tab_badge_hidden_when_no_character_bound():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("StatsTabBadge", true, false) as NotificationDot
	assert_not_null(badge)
	assert_false(badge.visible, "badge must hide when no character is bound")
