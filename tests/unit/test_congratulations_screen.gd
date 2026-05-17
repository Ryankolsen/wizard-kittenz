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
