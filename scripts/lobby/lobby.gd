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

# TEMP DIAGNOSTIC (issue #267, Phase 1 — remove in Phase 2 fix). On-screen
# readout so a host on a deployed Android release build can screenshot the
# identity/roster state that we cannot reproduce in the editor. NOT gated to
# debug because the bug only surfaces in the release build.
var _diag_label: Label = null

func _ready() -> void:
	_setup_diagnostics()  # TEMP DIAGNOSTIC (#267) — remove in Phase 2
	var lobby: NakamaLobby = GameState.lobby
	if lobby == null:
		_status_label.text = "Error: no active lobby"
		_render_diagnostics(null)  # TEMP DIAGNOSTIC (#267) — remove in Phase 2
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

	_render_diagnostics(state)  # TEMP DIAGNOSTIC (#267) — remove in Phase 2

func _on_lobby_updated(state: LobbyState) -> void:
	_refresh_from(state)

func _on_match_started(_match_id: String) -> void:
	# Build CoopSession from lobby, transitioning into the dungeon
	var lobby: NakamaLobby = GameState.lobby
	if lobby == null or lobby.lobby_state == null:
		return
	var chars: Dictionary = GameState.build_coop_chars_map()
	GameState.coop_session = CoopSession.new(
		lobby.lobby_state, chars,
		GameState.meta_tracker,
		GameState.local_player_id,
		lobby.dungeon_seed_sync,
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

# ===== TEMP DIAGNOSTIC (issue #267, Phase 1) — REMOVE ENTIRELY IN PHASE 2 =====
# Everything below renders an on-screen readout of the identity sources and the
# full roster directly on the lobby screen, so a host on the deployed Android
# release build can screenshot the state that we cannot reproduce in the editor.
# It is a transparent, click-through overlay anchored top-left and is updated on
# every lobby refresh. Not gated to debug — the bug only appears in release.

func _setup_diagnostics() -> void:
	_diag_label = Label.new()
	_diag_label.name = "Diag267"
	_diag_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_diag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diag_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_diag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_diag_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	_diag_label.add_theme_font_size_override("font_size", 16)
	add_child(_diag_label)

func _render_diagnostics(state: LobbyState) -> void:
	if _diag_label == null:
		return
	var lobby: NakamaLobby = GameState.lobby
	var session_id := "<no session>"
	if NakamaService.session != null:
		session_id = String(NakamaService.session.user_id)
	var lobby_local_id := lobby.local_player_id if lobby != null else "<no lobby>"
	var match_self := lobby.match_self_id if lobby != null else "<no lobby>"
	var path := lobby.entry_path if lobby != null else "<no lobby>"
	var lines: Array[String] = []
	lines.append("== DIAG #267 (temp) ==")
	lines.append("path: " + path)
	lines.append("session.user_id:")
	lines.append("  " + session_id)
	lines.append("GameState.local_player_id:")
	lines.append("  " + String(GameState.local_player_id))
	lines.append("lobby.local_player_id:")
	lines.append("  " + lobby_local_id)
	lines.append("match self_user.user_id:")
	lines.append("  " + match_self)
	if state == null:
		lines.append("roster: <null state>")
	else:
		var host := state.host()
		lines.append("host()=" + (host.player_id if host != null else "<null>"))
		lines.append("detected local is_host=" + ("Y" if _is_host else "N"))
		lines.append("roster (%d):" % state.players.size())
		for i in range(state.players.size()):
			var p := state.players[i]
			lines.append("[%d] host=%s ready=%s" % [i, ("Y" if p.is_host else "N"), ("Y" if p.ready else "N")])
			lines.append("    id=" + p.player_id)
			lines.append("    name=%s class=%s" % [p.kitten_name, p.class_name_str])
	_diag_label.text = "\n".join(lines)
# ===== END TEMP DIAGNOSTIC (#267) =============================================
