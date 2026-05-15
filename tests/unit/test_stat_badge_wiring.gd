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

func test_pause_menu_has_stats_tab_badge_hidden_by_default():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var badge = scene.find_child("StatsTabBadge", true, false)
	assert_not_null(badge, "pause_menu.tscn must contain a node named StatsTabBadge")
	assert_true(badge is Label, "StatsTabBadge must be a Label")
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
	var badge = scene.find_child("StatsTabBadge", true, false) as Label
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
	var badge = scene.find_child("StatsTabBadge", true, false) as Label
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
	var badge = scene.find_child("StatsTabBadge", true, false) as Label
	assert_false(badge.visible)
	c.skill_points = 5
	await get_tree().process_frame
	assert_true(badge.visible, "badge polls per frame — must turn on when points appear")
