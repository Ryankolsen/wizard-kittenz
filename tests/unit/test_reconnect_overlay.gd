extends GutTest

# Tests for ReconnectOverlay (#641). The overlay binds to GameState's
# ReconnectDriver and toggles its own visibility / state; it holds no
# reconnect logic of its own.

const RECONNECT_OVERLAY := preload("res://scenes/reconnect_overlay.tscn")

class FakeDriver extends ReconnectDriver:
	var cancel_calls := 0
	func cancel_reconnect() -> void:
		cancel_calls += 1

var _orig_driver: ReconnectDriver

func before_each():
	_orig_driver = GameState.reconnect_driver

func after_each():
	GameState.reconnect_driver = _orig_driver
	GameState.set_lobby(null)

func _make_overlay(driver: FakeDriver):
	GameState.reconnect_driver = driver
	var scene = RECONNECT_OVERLAY.instantiate()
	scene.menu_scene_path = ""  # never change scenes under test
	add_child_autofree(scene)
	return scene

func _new_driver() -> FakeDriver:
	var d := FakeDriver.new()
	autofree(d)
	return d

func test_overlay_scene_has_message_and_cancel_button():
	var scene = RECONNECT_OVERLAY.instantiate()
	var msg = scene.find_child("Message", true, false) as Label
	assert_not_null(msg)
	assert_eq(msg.text, "Reconnecting…")
	assert_not_null(scene.find_child("CancelButton", true, false) as Button)
	assert_not_null(scene.find_child("BackToMenuButton", true, false) as Button)
	scene.free()

func test_overlay_hidden_by_default():
	var scene = _make_overlay(_new_driver())
	assert_false(scene.visible)

func test_overlay_shows_on_reconnect_started():
	var d := _new_driver()
	var scene = _make_overlay(d)
	d.reconnect_started.emit()
	assert_true(scene.visible)
	assert_eq((scene.find_child("Message", true, false) as Label).text, "Reconnecting…")
	assert_true((scene.find_child("CancelButton", true, false) as Button).visible)
	assert_false((scene.find_child("BackToMenuButton", true, false) as Button).visible)

func test_overlay_hides_on_reconnect_succeeded():
	var d := _new_driver()
	var scene = _make_overlay(d)
	d.reconnect_started.emit()
	d.reconnect_succeeded.emit()
	assert_false(scene.visible)

func test_overlay_shows_error_state_on_reconnect_exhausted():
	var d := _new_driver()
	var scene = _make_overlay(d)
	d.reconnect_started.emit()
	d.reconnect_exhausted.emit()
	assert_true(scene.visible)
	assert_eq((scene.find_child("Message", true, false) as Label).text, "Connection lost")
	assert_false((scene.find_child("CancelButton", true, false) as Button).visible)
	assert_true((scene.find_child("BackToMenuButton", true, false) as Button).visible)

func test_cancel_button_calls_driver_cancel_reconnect():
	var d := _new_driver()
	var scene = _make_overlay(d)
	d.reconnect_started.emit()
	(scene.find_child("CancelButton", true, false) as Button).pressed.emit()
	assert_eq(d.cancel_calls, 1)

func test_back_to_menu_action_triggers_leave_flow():
	var d := _new_driver()
	var lobby := NakamaLobby.new()
	GameState.set_lobby(lobby)
	var scene = _make_overlay(d)
	d.reconnect_exhausted.emit()
	(scene.find_child("BackToMenuButton", true, false) as Button).pressed.emit()
	assert_null(GameState.lobby, "leave flow must clear the lobby like lobby.gd/pause_menu.gd")
	assert_false(scene.visible)

func test_overlay_rebinds_to_new_driver():
	var a := _new_driver()
	var b := _new_driver()
	var scene = _make_overlay(a)
	GameState.reconnect_driver = b
	scene._bind_to_current_driver()
	a.reconnect_started.emit()
	assert_false(scene.visible, "stale driver must be ignored")
	b.reconnect_started.emit()
	assert_true(scene.visible)
