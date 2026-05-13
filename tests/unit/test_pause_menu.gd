extends GutTest

# Walking skeleton for the PauseMenu (#44, parent PRD #42). The menu is a
# CanvasLayer overlay opened from the HUD's Pause button. Branch:
#   - solo (GameState.coop_session == null / inactive): freeze tree
#   - multiplayer (active CoopSession): show overlay only, tree stays live
#
# These tests pin the contract — they don't exercise submenus (#47–#50)
# or quit-dungeon save/resume (#45, #46). Those land in follow-up issues.

func after_each():
	# Defensive — a failing open() in solo mode could leave the tree paused
	# and poison every subsequent test that polls _process.
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_pause_menu_scene_has_resume_button():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var btn = scene.find_child("Resume", true, false)
	assert_not_null(btn, "pause_menu.tscn must have a node named Resume")
	scene.free()

func test_open_pauses_tree_in_solo_mode():
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true(get_tree().paused, "solo open must pause the scene tree")
	get_tree().paused = false

func test_resume_unpauses_tree():
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.close()
	assert_false(get_tree().paused, "close must unpause the scene tree")

func test_is_multiplayer_false_when_coop_session_null():
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	assert_false(scene.is_multiplayer(),
		"is_multiplayer() must be false when coop_session is null")

func test_pause_menu_process_mode_is_always():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	assert_eq(scene.process_mode, Node.PROCESS_MODE_ALWAYS,
		"PauseMenu must process while tree is paused")
	scene.free()

func test_open_makes_menu_visible():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true(scene.visible, "open() must show the overlay")
	get_tree().paused = false

func test_close_hides_menu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.close()
	assert_false(scene.visible, "close() must hide the overlay")

func test_hud_has_pause_button():
	var hud = load("res://scenes/hud.tscn").instantiate()
	var btn = hud.find_child("PauseButton", true, false)
	assert_not_null(btn, "HUD must expose a PauseButton during dungeon runs")
	assert_true(btn is Button, "PauseButton must be a Button")
	hud.free()
