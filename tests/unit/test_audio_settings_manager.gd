extends GutTest

const AudioSettings := preload("res://scripts/core/audio_settings_manager.gd")

# Settings submenu — Audio sliders (PRD #42 / #49). Pins the
# AudioSettings contract (linear→dB apply, JSON round-trip,
# defaults on missing file) plus the scene shape and slider→manager
# wiring inside pause_menu.tscn.

const TEST_PATH := "user://test_audio_settings.json"

func after_each():
	DirAccess.remove_absolute(TEST_PATH)
	get_tree().paused = false

# --- AudioSettings unit tests ---

func test_pause_menu_has_settings_submenu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var submenu = scene.find_child("SettingsSubmenu", true, false)
	assert_not_null(submenu, "pause_menu.tscn must contain SettingsSubmenu")
	scene.free()

func test_settings_submenu_has_bgm_and_sfx_sliders():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var bgm = scene.find_child("BGMSlider", true, false)
	var sfx = scene.find_child("SFXSlider", true, false)
	assert_not_null(bgm, "BGMSlider must exist")
	assert_not_null(sfx, "SFXSlider must exist")
	assert_true(bgm is HSlider, "BGMSlider must be an HSlider")
	assert_true(sfx is HSlider, "SFXSlider must be an HSlider")
	scene.free()

func test_set_bgm_volume_updates_audio_server():
	var bus_idx := AudioServer.get_bus_index("BGM")
	if bus_idx < 0:
		# Bus not configured in test env; the manager no-ops safely.
		# Verify the call doesn't crash and skip the dB assertion.
		AudioSettings.set_bgm_volume(0.5)
		return
	AudioSettings.set_bgm_volume(0.5)
	var db := AudioServer.get_bus_volume_db(bus_idx)
	assert_true(db > -80.0, "BGM bus volume must be set above mute floor")

func test_set_sfx_volume_updates_audio_server():
	var bus_idx := AudioServer.get_bus_index("SFX")
	if bus_idx < 0:
		AudioSettings.set_sfx_volume(0.5)
		return
	AudioSettings.set_sfx_volume(0.5)
	var db := AudioServer.get_bus_volume_db(bus_idx)
	assert_true(db > -80.0, "SFX bus volume must be set above mute floor")

func test_audio_settings_persist_and_reload():
	AudioSettings.save_settings({"bgm": 0.8, "sfx": 0.4}, TEST_PATH)
	var loaded := AudioSettings.load_settings(TEST_PATH)
	assert_eq(loaded.get("bgm"), 0.8, "BGM volume must survive save/load")
	assert_eq(loaded.get("sfx"), 0.4, "SFX volume must survive save/load")

func test_load_settings_missing_file_returns_defaults():
	var loaded := AudioSettings.load_settings("user://no_such_file.json")
	assert_eq(loaded.get("bgm"), 1.0, "default BGM must be 1.0")
	assert_eq(loaded.get("sfx"), 1.0, "default SFX must be 1.0")

func test_zero_volume_maps_to_mute_floor():
	# Mute (linear 0.0) should clamp to the floor rather than passing
	# -inf to AudioServer (linear_to_db(0) is -inf in Godot, which
	# AudioServer rejects with a warning).
	var bus_idx := AudioServer.get_bus_index("BGM")
	if bus_idx < 0:
		AudioSettings.set_bgm_volume(0.0)
		return
	AudioSettings.set_bgm_volume(0.0)
	var db := AudioServer.get_bus_volume_db(bus_idx)
	assert_almost_eq(db, -80.0, 0.01, "Linear 0.0 must clamp to mute floor")

# --- pause_menu wiring tests ---

func test_settings_button_enabled():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var btn := scene.find_child("Settings", true, false) as Button
	assert_not_null(btn, "Settings button must exist")
	assert_false(btn.disabled, "Settings button must be enabled")
	scene.free()

func test_open_settings_submenu_hides_main_and_shows_settings():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_settings_submenu()
	var main := scene.find_child("MainMenu", true, false) as Control
	var settings := scene.find_child("SettingsSubmenu", true, false) as Control
	assert_false(main.visible, "MainMenu must be hidden when SettingsSubmenu is open")
	assert_true(settings.visible, "SettingsSubmenu must be visible after open_settings_submenu")

func test_settings_back_returns_to_main_menu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_settings_submenu()
	scene.close_settings_submenu()
	var main := scene.find_child("MainMenu", true, false) as Control
	var settings := scene.find_child("SettingsSubmenu", true, false) as Control
	assert_true(main.visible, "MainMenu must be visible after settings Back")
	assert_false(settings.visible, "SettingsSubmenu must be hidden after Back")

func test_slider_change_persists_to_disk():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	# Clear any prior save so this test is deterministic.
	DirAccess.remove_absolute(AudioSettings.DEFAULT_PATH)
	var bgm := scene.find_child("BGMSlider", true, false) as HSlider
	var sfx := scene.find_child("SFXSlider", true, false) as HSlider
	bgm.value = 0.3
	sfx.value = 0.7
	var loaded := AudioSettings.load_settings()
	assert_almost_eq(float(loaded["bgm"]), 0.3, 0.01,
		"Moving BGM slider must persist its value")
	assert_almost_eq(float(loaded["sfx"]), 0.7, 0.01,
		"Moving SFX slider must persist its value")
	DirAccess.remove_absolute(AudioSettings.DEFAULT_PATH)
