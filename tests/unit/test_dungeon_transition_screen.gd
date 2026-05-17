extends GutTest

# Scene-layer tests for the dungeon-transition flow. PRD #52 / #61
# moved finalize + reload behind a player-driven confirmation; PRD
# #132 (issue #135) replaced the pause-menu-with-Continue-button
# surface with a dedicated CongratulationsScreen overlay. The
# boss-cleared edge still calls _run_controller.transition() —
# main_scene now mounts CongratulationsScreen on dungeon_transitioned
# and wires its Next Floor button to _finalize_and_reload.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

func before_each() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func after_each() -> void:
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func _install_solo_character() -> void:
	var gs := get_node("/root/GameState")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN))

func test_on_dungeon_completed_does_not_immediately_reload() -> void:
	# AC: dungeon loading is deferred until the player dismisses the
	# congratulations screen. Pin that the boss-cleared edge calls
	# transition() (which emits dungeon_transitioned) instead of going
	# straight to _finalize_and_reload. We can't observe the absence of
	# reload_current_scene easily, but we CAN observe that
	# dungeon_run_controller is still non-null after the handler runs —
	# _finalize_completed_run clears it, so its absence proves finalize
	# didn't happen.
	_install_solo_character()
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	var gs := get_node("/root/GameState")
	var rc: DungeonRunController = gs.dungeon_run_controller
	assert_not_null(rc, "precondition: solo path installs a run controller")

	watch_signals(rc)
	inst._on_dungeon_completed()

	assert_signal_emitted(rc, "dungeon_transitioned",
		"_on_dungeon_completed must route through transition()")
	assert_not_null(gs.dungeon_run_controller,
		"finalize is deferred — run controller stays live until Next Floor")

func test_on_dungeon_transitioned_mounts_congratulations_screen() -> void:
	# AC: dungeon_transitioned shows the CongratulationsScreen overlay
	# instead of jumping into the pause menu. The screen mounts as a
	# direct child of main_scene.
	_install_solo_character()
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	inst._on_dungeon_transitioned()

	var screen := inst.find_child("CongratulationsScreen", false, false)
	assert_not_null(screen, "CongratulationsScreen must mount under main_scene")
	assert_true(screen is CongratulationsScreen)

func test_congratulations_screen_next_floor_wires_to_finalize_and_reload() -> void:
	# Pin that main_scene subscribes its Next Floor handler to the
	# screen's signal so pressing Next Floor drives the deferred
	# finalize + reload path.
	_install_solo_character()
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	inst._on_dungeon_transitioned()

	var screen: CongratulationsScreen = inst.find_child("CongratulationsScreen", false, false)
	assert_not_null(screen)
	assert_true(screen.next_floor_pressed.is_connected(inst._on_congrats_next_floor_pressed),
		"main_scene must subscribe to next_floor_pressed so Next Floor triggers reload")

func test_pause_menu_open_for_transition_emits_transition_continued() -> void:
	# Regression: PauseMenu still exposes open_for_dungeon_transition +
	# the transition_continued signal because the Update Character
	# button (slice #136) will reuse the same Continue surface. This
	# pins the PauseMenu's own contract independently of main_scene.
	_install_solo_character()
	var pm: CanvasLayer = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(pm)
	pm.open_for_dungeon_transition()

	var panel := pm.find_child("StatsPanel", true, false) as StatsTabPanel
	assert_true(panel.get_continue_button().visible)
	watch_signals(pm)
	panel.get_continue_button().emit_signal("pressed")

	assert_signal_emitted(pm, "transition_continued",
		"pause menu re-emits transition_continued on Continue press")
	assert_false(pm.visible, "menu closes after Continue press")

func test_close_during_transition_mode_emits_transition_continued() -> void:
	# Regression: pressing Back → Resume while open_for_dungeon_transition
	# is active must still emit transition_continued so future callers
	# (slice #136 Update Character flow) don't get stranded on the menu.
	_install_solo_character()
	var pm: CanvasLayer = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(pm)
	pm.open_for_dungeon_transition()

	watch_signals(pm)
	pm.close_character_submenu()
	pm.close()

	assert_signal_emitted(pm, "transition_continued",
		"Back → Resume during transition flow must emit transition_continued")
	assert_false(pm.visible, "menu must close after Back → Resume in transition mode")

func test_close_during_transition_mode_hides_continue_button() -> void:
	_install_solo_character()
	var pm: CanvasLayer = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(pm)
	pm.open_for_dungeon_transition()

	pm.close_character_submenu()
	pm.close()

	var stats_panel := pm.find_child("StatsPanel", true, false) as StatsTabPanel
	var btn := stats_panel.get_continue_button()
	assert_false(btn.visible, "Continue button must be hidden after transition close")
