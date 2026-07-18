extends GutTest

# PRD #132 / issue #135 — CongratulationsScreen is a CanvasLayer
# overlay that displays the post-floor headline and the four
# FloorRunSummary stats and emits typed signals when its buttons
# are pressed. Caller (main_scene) owns the handler wiring.

const SCENE_PATH := "res://scenes/congratulations_screen.tscn"

func _instantiate() -> CongratulationsScreen:
	var scene: CongratulationsScreen = load(SCENE_PATH).instantiate()
	add_child_autofree(scene)
	return scene

func test_scene_has_required_nodes():
	var s := _instantiate()
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/Headline"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/Stats/FloorLabel"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/Stats/EnemiesLabel"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/Stats/XPLabel"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/Stats/GoldLabel"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/ButtonRow/NextFloor"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/ButtonRow/UpdateCharacter"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/ButtonRow/SaveAndExit"))

func test_populate_sets_headline_text():
	var s := _instantiate()
	var summary := FloorRunSummary.new(1, 0, 0, 0)
	s.populate(summary, "Test message")
	var headline: Label = s.get_node("Backdrop/Center/Panel/VBox/Headline")
	assert_eq(headline.text, "Test message")

func test_populate_sets_stat_labels():
	var s := _instantiate()
	var summary := FloorRunSummary.new(3, 17, 250, 88)
	s.populate(summary, "msg")
	var floor_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/FloorLabel")
	var enemies_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/EnemiesLabel")
	var xp_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/XPLabel")
	var gold_lbl: Label = s.get_node("Backdrop/Center/Panel/VBox/Stats/GoldLabel")
	assert_true(floor_lbl.text.find("3") != -1, "floor label should contain '3', got '%s'" % floor_lbl.text)
	assert_true(enemies_lbl.text.find("17") != -1, "enemies label should contain '17', got '%s'" % enemies_lbl.text)
	assert_true(xp_lbl.text.find("250") != -1, "xp label should contain '250', got '%s'" % xp_lbl.text)
	assert_true(gold_lbl.text.find("88") != -1, "gold label should contain '88', got '%s'" % gold_lbl.text)

func test_next_floor_pressed_fires_on_button_press():
	var s := _instantiate()
	watch_signals(s)
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/NextFloor")
	btn.pressed.emit()
	assert_signal_emitted(s, "next_floor_pressed")

func test_update_character_pressed_fires_on_button_press():
	var s := _instantiate()
	watch_signals(s)
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/UpdateCharacter")
	btn.pressed.emit()
	assert_signal_emitted(s, "update_character_pressed")

func test_update_character_pressed_signal_declared():
	# PRD #132 / issue #136 — main_scene relies on the typed
	# update_character_pressed signal to drive the pause-menu open path.
	# Pin the declaration so a rename can't silently break that wiring.
	var s := _instantiate()
	assert_true(s.has_signal("update_character_pressed"),
		"CongratulationsScreen must declare 'update_character_pressed' signal")

func test_save_and_exit_pressed_fires_on_button_press():
	var s := _instantiate()
	watch_signals(s)
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/SaveAndExit")
	btn.pressed.emit()
	assert_signal_emitted(s, "save_and_exit_pressed")

func test_save_and_exit_pressed_signal_declared():
	# PRD #132 / issue #137 — main_scene relies on the typed
	# save_and_exit_pressed signal to drive the save + scene-change path.
	# Pin the declaration so a rename can't silently break that wiring.
	var s := _instantiate()
	assert_true(s.has_signal("save_and_exit_pressed"),
		"CongratulationsScreen must declare 'save_and_exit_pressed' signal")

# --- #416: panel stays within viewport width on narrow (phone) aspect ---
#
# The real OS viewport can't be resized in the headless test runner (the
# project's fixed "canvas_items" stretch resolution snaps it straight
# back), so these tests drive the same _update_panel_width(vp_width) seam
# the real get_viewport().size_changed handler calls, passing an explicit
# narrow/wide width to stand in for the viewport.

const NARROW_VIEWPORT_WIDTH := 320.0
const WIDE_VIEWPORT_WIDTH := 800.0

func test_panel_width_fits_narrow_viewport():
	var s := _instantiate()
	s.populate(FloorRunSummary.new(1, 0, 0, 0), "Test message")
	await get_tree().process_frame
	await get_tree().process_frame
	s._update_panel_width(NARROW_VIEWPORT_WIDTH)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = s.get_node("Backdrop/Center/Panel")
	assert_lte(panel.size.x, NARROW_VIEWPORT_WIDTH,
		"Panel width must not exceed the narrow viewport width")

func test_headline_and_waiting_label_wrap_and_button_row_fits_narrow_viewport():
	var s := _instantiate()
	s.populate(FloorRunSummary.new(1, 0, 0, 0),
		"A very long congratulatory headline that should reflow instead of widening the panel",
		false)
	await get_tree().process_frame
	await get_tree().process_frame
	s._update_panel_width(NARROW_VIEWPORT_WIDTH)
	await get_tree().process_frame
	await get_tree().process_frame
	var headline: Label = s.get_node("Backdrop/Center/Panel/VBox/Headline")
	var waiting_label: Label = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow/WaitingLabel")
	assert_ne(headline.autowrap_mode, TextServer.AUTOWRAP_OFF,
		"Headline must have wrapping enabled")
	assert_ne(waiting_label.autowrap_mode, TextServer.AUTOWRAP_OFF,
		"WaitingLabel must have wrapping enabled")
	var panel: Control = s.get_node("Backdrop/Center/Panel")
	var button_row: Control = s.get_node("Backdrop/Center/Panel/VBox/ButtonRow")
	assert_lte(button_row.size.x, panel.size.x,
		"ButtonRow must fit within the constrained panel width, not force it wider")

func test_panel_does_not_shrink_below_natural_size_on_wide_viewport():
	var s := _instantiate()
	s.populate(FloorRunSummary.new(1, 0, 0, 0), "Test message")
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = s.get_node("Backdrop/Center/Panel")
	var natural_width := panel.size.x
	s._update_panel_width(WIDE_VIEWPORT_WIDTH)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(panel.size.x, natural_width, 1.0,
		"Panel must keep its normal unconstrained width on a wide viewport")

func test_leader_panel_fits_narrow_viewport():
	var s := _instantiate()
	s.populate(FloorRunSummary.new(1, 0, 0, 0), "Test message", true)
	await get_tree().process_frame
	await get_tree().process_frame
	s._update_panel_width(NARROW_VIEWPORT_WIDTH)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = s.get_node("Backdrop/Center/Panel")
	assert_lte(panel.size.x, NARROW_VIEWPORT_WIDTH,
		"Solo/leader panel (single button) must also fit within the narrow viewport")
