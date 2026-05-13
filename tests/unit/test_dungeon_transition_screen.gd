extends GutTest

# Scene-layer tests for the dungeon-transition stat-allocation screen
# (PRD #52 / #61). After this slice the boss-cleared edge no longer
# auto-reloads — main_scene calls _run_controller.transition(), which
# emits dungeon_transitioned, which opens the pause menu in
# transition mode (Stats tab + Continue button). The Continue button's
# transition_continued signal then drives the deferred finalize +
# reload.

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
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE))

func test_on_dungeon_completed_does_not_immediately_reload() -> void:
	# AC: dungeon loading is deferred until the player dismisses the
	# allocation screen. Pin that the boss-cleared edge calls
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
		"finalize is deferred — run controller stays live until Continue")

func test_on_dungeon_transitioned_opens_pause_menu_to_stats_tab() -> void:
	# AC: scene layer opens pause menu to Stats tab when dungeon_transitioned
	# fires. The pause menu lazy-instances under the HUD; after the handler
	# the HUD must own a visible PauseMenu with the Stats tab visible.
	_install_solo_character()
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	inst._on_dungeon_transitioned()

	# Reach in through the HUD — same pattern HUD._on_pause_pressed uses
	# to materialize the menu.
	var hud: HUD = inst.get_node("HUD")
	var pm: CanvasLayer = hud._pause_menu
	assert_not_null(pm, "transition flow must instantiate the pause menu")
	assert_true(pm.visible, "pause menu must be open")
	var stats_panel := pm.find_child("StatsPanel", true, false) as StatsTabPanel
	assert_not_null(stats_panel, "StatsPanel must exist")
	assert_true(stats_panel.visible, "Stats tab must be the visible tab")

func test_on_dungeon_transitioned_shows_continue_button() -> void:
	# AC: A "Continue" button on the Stats tab — visible only in the
	# transition flow. The normal pause-menu open() path does not show it.
	_install_solo_character()
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	inst._on_dungeon_transitioned()

	var hud: HUD = inst.get_node("HUD")
	var pm: CanvasLayer = hud._pause_menu
	var stats_panel := pm.find_child("StatsPanel", true, false) as StatsTabPanel
	var btn := stats_panel.get_continue_button()
	assert_true(btn.visible, "Continue button must be visible in transition flow")
	assert_false(btn.disabled,
		"Continue button must be enabled even at 0 skill_points "
		+ "(immediately-available dismissal)")

func test_pause_menu_open_for_transition_emits_transition_continued() -> void:
	# AC: Continue button closes the screen and resumes dungeon loading.
	# Verify the pause menu's transition_continued signal fires when the
	# Continue button is pressed, and the menu closes. The actual
	# finalize + reload path lives in main_scene._on_transition_continued
	# which is exercised end-to-end in production; here we pin the menu's
	# own contract so the wire stays sound across refactors.
	_install_solo_character()
	# Stand up the pause menu directly (not via main_scene) so the
	# main_scene -> transition_continued -> reload listener doesn't
	# clobber the GUT runner.
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

func test_main_scene_subscribes_to_transition_continued() -> void:
	# Pin that main_scene wires _on_transition_continued as a listener on
	# the PauseMenu's transition_continued signal so production drives the
	# finalize + reload step. Inspect the signal's connections directly.
	_install_solo_character()
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	inst._on_dungeon_transitioned()

	var hud: HUD = inst.get_node("HUD")
	var pm: CanvasLayer = hud._pause_menu
	assert_true(pm.transition_continued.is_connected(inst._on_transition_continued),
		"main_scene must subscribe to transition_continued so Continue triggers reload")
