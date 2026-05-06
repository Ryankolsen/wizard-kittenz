class_name NakamaLobby
extends RefCounted

const OP_PLAYER_INFO: int = 1
const OP_READY_TOGGLE: int = 2
const OP_START_MATCH: int = 3

signal lobby_updated(state: LobbyState)
signal match_started(match_id: String)
signal join_failed(reason: String)

var lobby_state: LobbyState = null
var local_player_id: String = ""

var _socket = null  # NakamaSocket, untyped to avoid preload at class scope
var _session = null # NakamaSession
var _match_id: String = ""

func _init(socket = null, session = null) -> void:
	_socket = socket
	_session = session
	if socket != null:
		socket.received_match_presence.connect(_on_match_presence)
		socket.received_match_state.connect(_on_match_state)

# --- Async wire methods -------------------------------------------------------

func create_async(room_code: String, local_player: LobbyPlayer) -> bool:
	if _socket == null:
		join_failed.emit("No socket")
		return false
	var match_result = await _socket.create_match_async(room_code)
	if match_result.is_exception():
		join_failed.emit("Failed to create room: " + match_result.get_exception().message)
		return false
	_match_id = match_result.match_id
	local_player_id = local_player.player_id
	lobby_state = LobbyState.new(room_code)
	local_player.is_host = true
	lobby_state.add_player(local_player)
	# Broadcast our info to any late-joiners watching this match
	await send_player_info_async(local_player)
	lobby_updated.emit(lobby_state)
	return true

func join_async(room_code: String, local_player: LobbyPlayer) -> bool:
	if not RoomCodeValidator.is_valid(room_code):
		join_failed.emit("Invalid room code")
		return false
	if _socket == null:
		join_failed.emit("No socket")
		return false
	var match_id: String = await NakamaService.find_match_async(_session, room_code)
	if match_id == "":
		join_failed.emit("Room not found")
		return false
	var match_result = await _socket.join_match_async(match_id)
	if match_result.is_exception():
		join_failed.emit("Failed to join: " + match_result.get_exception().message)
		return false
	_match_id = match_result.match_id
	local_player_id = local_player.player_id
	lobby_state = LobbyState.new(room_code)
	lobby_state.add_player(local_player)
	# Populate from presences already in the match (excluding self)
	var existing: Array = []
	for p in match_result.presences:
		if p.user_id != local_player_id:
			existing.append({"user_id": p.user_id, "username": p.username})
	if not existing.is_empty():
		apply_joins(existing)
	# Announce ourselves to the existing players
	await send_player_info_async(local_player)
	lobby_updated.emit(lobby_state)
	return true

func send_player_info_async(player: LobbyPlayer) -> void:
	if _socket == null or _match_id == "":
		return
	var payload := {"kitten_name": player.kitten_name, "class_name": player.class_name_str}
	await _socket.send_match_state_async(_match_id, OP_PLAYER_INFO, JSON.stringify(payload))

func send_ready_async(is_ready: bool) -> void:
	if lobby_state == null:
		return
	lobby_state.set_ready(local_player_id, is_ready)
	lobby_updated.emit(lobby_state)
	if _socket == null or _match_id == "":
		return
	await _socket.send_match_state_async(_match_id, OP_READY_TOGGLE, JSON.stringify({"ready": is_ready}))

func request_start_async() -> bool:
	if lobby_state == null or not lobby_state.can_start():
		return false
	if _socket == null or _match_id == "":
		return false
	await _socket.send_match_state_async(_match_id, OP_START_MATCH, "{}")
	match_started.emit(_match_id)
	return true

func leave_async() -> void:
	if _socket != null and _match_id != "":
		await _socket.leave_match_async(_match_id)
	_match_id = ""
	lobby_state = null

# --- Internal state mutation (public for testability) -------------------------

# Applies a batch of joining presences (dicts with user_id / username keys).
# Skips the local player and duplicate ids. Emits lobby_updated.
func apply_joins(presences: Array) -> void:
	if lobby_state == null:
		return
	for p in presences:
		var uid: String = String(p.get("user_id", ""))
		var uname: String = String(p.get("username", ""))
		if uid == "" or uid == local_player_id:
			continue
		if lobby_state.find_player(uid) != null:
			continue
		lobby_state.add_player(LobbyPlayer.make(uid, uname, ""))
	lobby_updated.emit(lobby_state)

# Applies a batch of leaving presences. Emits lobby_updated.
func apply_leaves(presences: Array) -> void:
	if lobby_state == null:
		return
	for p in presences:
		var uid: String = String(p.get("user_id", ""))
		if uid != "":
			lobby_state.remove_player(uid)
	lobby_updated.emit(lobby_state)

# Routes a decoded match-state message to the appropriate LobbyState mutation.
func apply_state(op_code: int, sender_id: String, data: Dictionary) -> void:
	if lobby_state == null:
		return
	match op_code:
		OP_PLAYER_INFO:
			var p := lobby_state.find_player(sender_id)
			if p != null:
				p.kitten_name = String(data.get("kitten_name", p.kitten_name))
				p.class_name_str = String(data.get("class_name", p.class_name_str))
			lobby_updated.emit(lobby_state)
		OP_READY_TOGGLE:
			lobby_state.set_ready(sender_id, bool(data.get("ready", false)))
			lobby_updated.emit(lobby_state)
		OP_START_MATCH:
			match_started.emit(_match_id)

# --- Socket signal handlers ---------------------------------------------------

func _on_match_presence(event) -> void:
	if event.match_id != _match_id:
		return
	var joins: Array = []
	for p in event.joins:
		joins.append({"user_id": p.user_id, "username": p.username})
	var leaves: Array = []
	for p in event.leaves:
		leaves.append({"user_id": p.user_id})
	if not joins.is_empty():
		apply_joins(joins)
	if not leaves.is_empty():
		apply_leaves(leaves)

func _on_match_state(state) -> void:
	if state.match_id != _match_id:
		return
	var data_dict: Dictionary = {}
	if state.data != "":
		var parsed = JSON.parse_string(state.data)
		if parsed is Dictionary:
			data_dict = parsed
	apply_state(state.op_code, state.presence.user_id, data_dict)
