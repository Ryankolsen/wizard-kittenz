class_name LobbyScene
extends Control

@export var character_creation_scene_path: String = "res://scenes/character_creation.tscn"
@export var main_scene_path: String = "res://scenes/main.tscn"

@onready var _room_code_label: Label = $VBox/RoomCodeLabel
@onready var _players_box: VBoxContainer = $VBox/PlayersBox
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _ready_button: Button = $VBox/Buttons/ReadyButton
@onready var _start_button: Button = $VBox/Buttons/StartButton
@onready var _leave_button: Button = $VBox/Buttons/LeaveButton

var _is_ready: bool = false
var _is_host: bool = false

func _ready() -> void:
	var lobby: NakamaLobby = GameState.lobby
	if lobby == null:
		_status_label.text = "Error: no active lobby"
		return

	_room_code_label.text = "Room: " + (lobby.lobby_state.room_code if lobby.lobby_state else "???")
	_refresh_from(lobby.lobby_state)

	lobby.lobby_updated.connect(_on_lobby_updated)
	lobby.match_started.connect(_on_match_started)
	lobby.join_failed.connect(_on_join_failed)

	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)

func _refresh_from(state: LobbyState) -> void:
	if state == null:
		return
	_room_code_label.text = "Room: " + state.room_code

	# Rebuild roster rows
	for child in _players_box.get_children():
		child.queue_free()
	for p in state.players:
		var row := Label.new()
		var ready_str := "✓" if p.ready else "…"
		var host_str := " [Host]" if p.is_host else ""
		row.text = "%s  %s  (%s)%s  %s" % [ready_str, p.kitten_name, p.class_name_str, host_str, p.player_id.left(8)]
		_players_box.add_child(row)

	# Show Start button only for the host; enable only when all ready
	var host := state.host()
	_is_host = (host != null and host.player_id == GameState.local_player_id)
	_start_button.visible = _is_host
	_start_button.disabled = not state.can_start()

func _on_lobby_updated(state: LobbyState) -> void:
	_refresh_from(state)

func _on_match_started(_match_id: String) -> void:
	# Build CoopSession from lobby, transitioning into the dungeon
	var lobby: NakamaLobby = GameState.lobby
	if lobby == null or lobby.lobby_state == null:
		return
	var chars: Dictionary = {}
	if GameState.current_character != null:
		chars[GameState.local_player_id] = GameState.current_character
	GameState.coop_session = CoopSession.new(
		lobby.lobby_state, chars,
		GameState.meta_tracker,
		GameState.local_player_id
	)
	get_tree().change_scene_to_file(main_scene_path)

func _on_join_failed(reason: String) -> void:
	_status_label.text = "Error: " + reason

func _on_ready_pressed() -> void:
	_is_ready = not _is_ready
	_ready_button.text = "Not Ready" if _is_ready else "Ready"
	var lobby: NakamaLobby = GameState.lobby
	if lobby != null:
		lobby.send_ready_async(_is_ready)

func _on_start_pressed() -> void:
	var lobby: NakamaLobby = GameState.lobby
	if lobby != null:
		lobby.request_start_async()

func _on_leave_pressed() -> void:
	var lobby: NakamaLobby = GameState.lobby
	if lobby != null:
		lobby.leave_async()
	GameState.set_lobby(null)
	get_tree().change_scene_to_file(character_creation_scene_path)
