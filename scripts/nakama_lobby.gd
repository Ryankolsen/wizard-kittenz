class_name NakamaLobby
extends RefCounted

const OP_PLAYER_INFO: int = 1
const OP_READY_TOGGLE: int = 2
const OP_START_MATCH: int = 3
# In-match position broadcast. Payload: {"x": float, "y": float, "ts": float}.
# Sender id is taken from the socket presence, not the payload, so a client
# can't spoof another player's position.
const OP_POSITION: int = 4
# In-match enemy-killed broadcast. Payload: {"enemy_id": String, "xp": int}.
# killer_id is taken from the socket presence (not the payload) so a client
# can't spoof another player's kill credit. Inbound packets route through
# RemoteKillApplier on the receiving side: enemy_sync.apply_death gates
# duplicates idempotently and xp_broadcaster.on_enemy_killed fans XP to
# every party member's LocalXPRouter.
const OP_KILL: int = 5

signal lobby_updated(state: LobbyState)
signal match_started(match_id: String)
signal join_failed(reason: String)
# In-match position update from a remote player. GameState routes this into
# coop_session.network_sync.apply_remote_state when a session is active.
# Decoupled via signal so NakamaLobby stays testable without a live session
# and so the Player render layer (CoopPlayerLayer / RemoteKitten) can be
# wired without poking at the lobby internals.
signal position_received(player_id: String, position: Vector2, timestamp: float)
# In-match enemy-killed event from a remote player. GameState routes this
# into RemoteKillApplier.apply when a session is active. Decoupled via
# signal for the same reason as position_received — lets NakamaLobby be
# tested without a live CoopSession.
signal kill_received(enemy_id: String, killer_id: String, xp_value: int)

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

func send_position_async(now: float, position: Vector2) -> void:
	if _socket == null or _match_id == "":
		return
	var payload := {"x": position.x, "y": position.y, "ts": now}
	await _socket.send_match_state_async(_match_id, OP_POSITION, JSON.stringify(payload))

# Broadcasts a local kill to every match participant. Empty enemy_id is a
# defensive no-op — pre-spawn-layer / test fixture enemies don't have a
# stable id and would arrive on remote clients as an unkeyed packet that
# RemoteKillApplier would reject anyway. killer_id is intentionally NOT
# in the payload — Nakama tags every packet with the sender presence, so
# the receiving side reads killer_id off the socket envelope (matches the
# OP_POSITION anti-spoofing model).
func send_kill_async(enemy_id: String, _killer_id: String, xp_value: int) -> void:
	if enemy_id == "":
		return
	if _socket == null or _match_id == "":
		return
	var payload := {"enemy_id": enemy_id, "xp": xp_value}
	await _socket.send_match_state_async(_match_id, OP_KILL, JSON.stringify(payload))

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

# Routes a decoded match-state message to the appropriate LobbyState mutation
# or in-match signal emission. OP_POSITION and OP_KILL intentionally bypass
# the lobby_state == null guard — the lobby UI may already have torn down
# LobbyState on match start, but in-match packets keep flowing for the
# duration of the match.
func apply_state(op_code: int, sender_id: String, data: Dictionary) -> void:
	if op_code == OP_POSITION:
		_route_position(sender_id, data)
		return
	if op_code == OP_KILL:
		_route_kill(sender_id, data)
		return
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

# Decodes the OP_POSITION payload and emits position_received. Drops the
# packet silently when sender_id is missing, when sender_id matches the
# local player (echo of our own broadcast), or when x/y/ts keys are absent
# — a malformed payload from a future protocol mismatch shouldn't crash
# the render loop.
func _route_position(sender_id: String, data: Dictionary) -> void:
	if sender_id == "" or sender_id == local_player_id:
		return
	if not (data.has("x") and data.has("y") and data.has("ts")):
		return
	var pos := Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	var ts: float = float(data.get("ts", 0.0))
	position_received.emit(sender_id, pos, ts)

# Decodes the OP_KILL payload and emits kill_received. Self-echoes are
# dropped at the routing layer rather than relying on RemoteKillApplier's
# downstream apply_death idempotency: a self-echo would still pay the
# enemy_sync registry lookup and the broadcaster signal hop, and any
# logging downstream would falsely attribute a "remote kill" to our own
# kill. Empty enemy_id is dropped because it can't be gated downstream
# (apply_death rejects empty ids → false → caller can't distinguish a
# duplicate from a malformed packet).
func _route_kill(sender_id: String, data: Dictionary) -> void:
	if sender_id == "" or sender_id == local_player_id:
		return
	if not data.has("enemy_id"):
		return
	var enemy_id: String = String(data.get("enemy_id", ""))
	if enemy_id == "":
		return
	var xp_value: int = int(data.get("xp", 0))
	kill_received.emit(enemy_id, sender_id, xp_value)

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
