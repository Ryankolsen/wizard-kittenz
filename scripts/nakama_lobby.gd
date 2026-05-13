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
# Host-initiated pause / unpause broadcast. Empty payload — the sender
# presence on the receiving side is checked against the lobby host so only
# the party host (lobby creator) can pause / unpause for everyone.
# Distinct from the per-player soft-pause in #42's PauseMenu, which only
# overlays the local player's screen. OP_HOST_PAUSE freezes every client.
const OP_HOST_PAUSE: int = 6
const OP_HOST_UNPAUSE: int = 7

signal lobby_updated(state: LobbyState)
signal match_started(match_id: String)
signal join_failed(reason: String)
# Emitted exactly once per match when the dungeon seed agrees — host fires on
# host_mint via request_start_async, remote fires on apply_remote_seed via the
# OP_START_MATCH payload. Decoupled via signal so GameState/CoopSession can
# observe without poking dungeon_seed_sync internals. Re-emits across matches
# rely on _host_mint_match_seed calling reset() on a stale sync before the
# next host_mint so the previous match's agreed state doesn't suppress a
# fresh mint.
signal seed_agreed(seed: int)
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
# Host-initiated pause / unpause edges. Only fire on a real transition (the
# HostPauseState rising/falling-edge gate inside apply_state suppresses
# duplicate packets). The scene-tree bridge in GameState binds these to
# get_tree().paused so remote clients freeze in lockstep with the host's
# pause press.
signal host_paused()
signal host_unpaused()

var lobby_state: LobbyState = null
var local_player_id: String = ""
# Per-match agreed dungeon seed. Host mints inside request_start_async and ships
# the value in the OP_START_MATCH payload; remote applies in apply_state before
# match_started.emit so any subscriber (lobby UI → CoopSession) sees an agreed
# seed at the moment the match-started edge fires. Allocated once per lobby
# instance and reset() at the start of each match to support multi-run lobbies
# without re-allocating the sync.
var dungeon_seed_sync: DungeonSeedSync = DungeonSeedSync.new()
# Per-match host-initiated pause flag. Lives on the lobby (not CoopSession)
# because the host's pause press happens through the lobby's wire layer and
# the auto-release on host-disconnect (apply_leaves below) reads from the
# same lobby's presence list. Always non-null so call sites can read
# .is_paused() freely.
var host_pause_state: HostPauseState = HostPauseState.new()

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

# Returns true iff the local player is the lobby host. Host gate for the
# OP_HOST_PAUSE / OP_HOST_UNPAUSE send paths and for the receiving-side
# sender check in apply_state. Defensive on null lobby_state / missing host
# (returns false) so a malformed lobby never grants pause authority.
func is_local_host() -> bool:
	if lobby_state == null:
		return false
	var h := lobby_state.host()
	if h == null:
		return false
	return h.player_id != "" and h.player_id == local_player_id

# Host-only: broadcasts a pause and locally rising-edges host_pause_state +
# emits host_paused. Non-host callers are silent no-ops (the receiving-side
# apply_state would reject the packet anyway, but gating on the send side
# saves bandwidth + matches the OP_KILL pattern). Self-broadcast loops back
# through apply_state's host-id check, so the host's own paused edge fires
# through the same code path as remote clients.
func send_host_pause_async() -> void:
	if not is_local_host():
		return
	if not host_pause_state.set_paused(true):
		return
	host_paused.emit()
	if _socket == null or _match_id == "":
		return
	await _socket.send_match_state_async(_match_id, OP_HOST_PAUSE, "{}")

func send_host_unpause_async() -> void:
	if not is_local_host():
		return
	if not host_pause_state.set_paused(false):
		return
	host_unpaused.emit()
	if _socket == null or _match_id == "":
		return
	await _socket.send_match_state_async(_match_id, OP_HOST_UNPAUSE, "{}")

func request_start_async() -> bool:
	if lobby_state == null or not lobby_state.can_start():
		return false
	if _socket == null or _match_id == "":
		return false
	var seed := _host_mint_match_seed()
	await _socket.send_match_state_async(
		_match_id, OP_START_MATCH, JSON.stringify({"seed": seed})
	)
	match_started.emit(_match_id)
	return true

# Host-side seed prep, pulled out so a test can pin the precondition (lobby
# enters request_start_async with a fresh, agreed seed) without faking a real
# socket. Resets a stale sync from the previous match (the lobby instance is
# reused for multi-run sessions, so a second host_mint must not return the
# previous match's seed and ship the party back into the same dungeon).
# Returns the agreed seed for the caller to embed in the OP_START_MATCH
# payload.
func _host_mint_match_seed() -> int:
	if dungeon_seed_sync.is_agreed():
		dungeon_seed_sync.reset()
	var seed := dungeon_seed_sync.host_mint()
	seed_agreed.emit(seed)
	return seed

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
	# Snapshot the host id BEFORE remove_player runs — once the host's
	# LobbyPlayer is gone from the array, lobby_state.host() returns null
	# and we lose the ability to tell whether the leaver was the host.
	var pre_host := lobby_state.host()
	var pre_host_id: String = pre_host.player_id if pre_host != null else ""
	for p in presences:
		var uid: String = String(p.get("user_id", ""))
		if uid != "":
			lobby_state.remove_player(uid)
	# Auto-release on host-disconnect: if the lobby was host-paused and the
	# host just left, drop the pause so the remaining players aren't stuck
	# behind a "Host has paused" overlay forever. The issue spec ("if the
	# host disconnects while paused, the pause is released automatically").
	if pre_host_id != "" and lobby_state.find_player(pre_host_id) == null:
		if host_pause_state.set_paused(false):
			host_unpaused.emit()
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
	if op_code == OP_HOST_PAUSE:
		_route_host_pause(sender_id, true)
		return
	if op_code == OP_HOST_UNPAUSE:
		_route_host_pause(sender_id, false)
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
			_apply_remote_match_seed(data)
			match_started.emit(_match_id)

# Reads the seed from an OP_START_MATCH payload and applies it via the per-
# lobby DungeonSeedSync. No-op when the sync is already agreed (host's self-
# echo arrives after request_start_async already minted, so apply_remote_seed
# would reject the duplicate anyway — but skipping the reset avoids clobbering
# the host's minted seed if a future race orders the echo before the local
# mint). A missing or negative seed key is a no-op (legacy / corrupted
# payloads fall through to the existing match_started emit so the lobby UI
# still transitions).
func _apply_remote_match_seed(data: Dictionary) -> void:
	if dungeon_seed_sync.is_agreed():
		return
	if not data.has("seed"):
		return
	var seed: int = int(data.get("seed", -1))
	if seed < 0:
		return
	if dungeon_seed_sync.apply_remote_seed(seed):
		seed_agreed.emit(seed)

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

# Routes an OP_HOST_PAUSE / OP_HOST_UNPAUSE packet. Authority check: the
# sender presence must match the lobby's current host. A non-host client
# sending OP_HOST_PAUSE is silently dropped — the host gate lives on both
# the send side (is_local_host()) and the receive side so a misbehaving /
# tampered client can't desync the party. Empty sender_id is also dropped
# (defensive against a future presence-strip).
#
# Edge-gated through HostPauseState.set_paused — duplicate packets (a flaky
# wire double-delivering OP_HOST_PAUSE) don't re-emit host_paused.
func _route_host_pause(sender_id: String, paused: bool) -> void:
	if sender_id == "":
		return
	if lobby_state == null:
		return
	var h := lobby_state.host()
	if h == null or h.player_id != sender_id:
		return
	if not host_pause_state.set_paused(paused):
		return
	if paused:
		host_paused.emit()
	else:
		host_unpaused.emit()

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
