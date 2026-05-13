extends GutTest

# Settings submenu — Controls layout toggle (PRD #42 / #50). Pins the
# ControlsSettingsManager save/load contract, the scene shape inside
# SettingsSubmenu, the OptionButton wiring, and the TouchControls
# apply_layout behavior.

const ControlsSettings := preload("res://scripts/controls_settings_manager.gd")
const TEST_PATH := "user://test_controls.json"

func after_each():
	DirAccess.remove_absolute(TEST_PATH)
	DirAccess.remove_absolute(ControlsSettings.DEFAULT_PATH)

# --- Scene shape ---

func test_settings_submenu_has_controls_section():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var section = scene.find_child("ControlsSection", true, false)
	assert_not_null(section, "SettingsSubmenu must contain a ControlsSection node")
	scene.free()

func test_controls_section_has_layout_option():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var opt = scene.find_child("LayoutOption", true, false)
	assert_not_null(opt, "ControlsSection must contain a LayoutOption")
	assert_true(opt is OptionButton, "LayoutOption must be an OptionButton")
	assert_eq(opt.item_count, 2, "LayoutOption must have two layouts")
	scene.free()

# --- ControlsSettingsManager ---

func test_controls_layout_persists():
	ControlsSettings.save_layout("right_hand", TEST_PATH)
	var loaded := ControlsSettings.load_layout(TEST_PATH)
	assert_eq(loaded, "right_hand", "layout choice must survive save/load")

func test_load_layout_missing_file_returns_default():
	var layout := ControlsSettings.load_layout("user://no_controls.json")
	assert_eq(layout, "left_hand", "default layout must be left_hand")

func test_load_layout_invalid_value_falls_back_to_default():
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string('{"layout":"bogus"}')
	f.close()
	var layout := ControlsSettings.load_layout(TEST_PATH)
	assert_eq(layout, "left_hand", "invalid layout must fall back to default")

# --- pause_menu wiring ---

func test_layout_option_selection_persists():
	DirAccess.remove_absolute(ControlsSettings.DEFAULT_PATH)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	var opt := scene.find_child("LayoutOption", true, false) as OptionButton
	opt.select(1)
	opt.item_selected.emit(1)
	assert_eq(ControlsSettings.load_layout(), "right_hand",
		"Selecting right-hand layout must persist to disk")

func test_open_settings_submenu_populates_layout_option():
	# Pre-seed a right-hand preference and verify the OptionButton lands
	# on the right-hand item when the submenu is opened.
	ControlsSettings.save_layout("right_hand")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_settings_submenu()
	var opt := scene.find_child("LayoutOption", true, false) as OptionButton
	assert_eq(opt.selected, 1,
		"Opening Settings must populate LayoutOption from persisted layout")

# --- TouchControls apply_layout ---

func test_touch_controls_apply_layout_mirrors_joystick_right_hand():
	var scene = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(scene)
	var joystick := scene.get_node("Joystick") as Control
	var original_left := joystick.offset_left
	scene.apply_layout("right_hand")
	assert_true(joystick.offset_left > original_left,
		"Right-hand layout must move joystick toward the right side")

func test_touch_controls_apply_layout_left_hand_is_noop():
	var scene = load("res://scenes/touch_controls.tscn").instantiate()
	add_child_autofree(scene)
	var joystick := scene.get_node("Joystick") as Control
	var original_left := joystick.offset_left
	scene.apply_layout("left_hand")
	assert_eq(joystick.offset_left, original_left,
		"Left-hand layout matches the .tscn shape — no offset change")
