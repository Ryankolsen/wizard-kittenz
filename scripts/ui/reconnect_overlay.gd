class_name ReconnectOverlay
extends CanvasLayer

# Reconnect overlay (#641, PRD #636). Binds to GameState.reconnect_driver and
# toggles visibility / state; holds no reconnect logic. Shown to every player
# whose own connection drops (not host-specific). Does not need
# PROCESS_MODE_ALWAYS: a connection drop does not pause the tree.
#
# States: hidden -> reconnecting (message + cancel) -> hidden on success, or
# exhausted ("Connection lost" + back to menu) on exhaustion/cancel.

const RECONNECTING_TEXT := "Reconnecting…"
const EXHAUSTED_TEXT := "Connection lost"

# Same destination as lobby.gd / pause_menu.gd's leave flow. Empty skips the
# scene change (tests).
var menu_scene_path := "res://scenes/character_creation.tscn"

var _bound_driver: ReconnectDriver = null
@onready var _message: Label = find_child("Message", true, false)
@onready var _cancel_button: Button = find_child("CancelButton", true, false)
@onready var _back_button: Button = find_child("BackToMenuButton", true, false)

func _ready() -> void:
	visible = false
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_back_button.pressed.connect(_on_back_to_menu_pressed)
	_bind_to_current_driver()

# Rebindable; defensively disconnects from any prior driver.
func _bind_to_current_driver() -> void:
	if _bound_driver != null:
		if _bound_driver.reconnect_started.is_connected(_on_reconnect_started):
			_bound_driver.reconnect_started.disconnect(_on_reconnect_started)
		if _bound_driver.reconnect_succeeded.is_connected(_on_reconnect_succeeded):
			_bound_driver.reconnect_succeeded.disconnect(_on_reconnect_succeeded)
		if _bound_driver.reconnect_exhausted.is_connected(_on_reconnect_exhausted):
			_bound_driver.reconnect_exhausted.disconnect(_on_reconnect_exhausted)
		_bound_driver = null
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var driver: ReconnectDriver = gs.reconnect_driver
	if driver == null:
		return
	_bound_driver = driver
	driver.reconnect_started.connect(_on_reconnect_started)
	driver.reconnect_succeeded.connect(_on_reconnect_succeeded)
	driver.reconnect_exhausted.connect(_on_reconnect_exhausted)

func _on_reconnect_started() -> void:
	_message.text = RECONNECTING_TEXT
	_cancel_button.visible = true
	_back_button.visible = false
	visible = true

func _on_reconnect_succeeded() -> void:
	visible = false

func _on_reconnect_exhausted() -> void:
	_message.text = EXHAUSTED_TEXT
	_cancel_button.visible = false
	_back_button.visible = true
	visible = true

func _on_cancel_pressed() -> void:
	if _bound_driver != null:
		_bound_driver.cancel_reconnect()

# Mirrors lobby.gd _on_leave_pressed / pause_menu.gd confirm_quit_dungeon:
# leave the match, drop the lobby and co-op session, return to the menu.
func _on_back_to_menu_pressed() -> void:
	visible = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		if gs.lobby != null:
			gs.lobby.leave_async()
			gs.set_lobby(null)
		if gs.coop_session != null:
			gs.coop_session.end()
			gs.coop_session = null
	if menu_scene_path != "":
		get_tree().change_scene_to_file(menu_scene_path)
