class_name CoopPlayerLayer
extends Node2D

# Renders one RemoteKitten per remote player_id in the active lobby.
# Sibling of the local Player node in the dungeon scene.
#
# Lifecycle:
#   - _ready resolves GameState.lobby + GameState.coop_session and reconciles
#     once against the current roster (so a player joining mid-route between
#     scene change and _ready still sees existing teammates).
#   - lobby.lobby_updated drives subsequent reconciles. Each reconcile diffs
#     the current roster against the children map, spawns missing kittens
#     and frees departed ones. Idempotent — re-applying the same roster is
#     a no-op.
#   - The local player_id is always skipped: the local Player node already
#     renders that kitten.
#
# Solo path: when GameState.lobby or GameState.coop_session is null, the
# layer renders nothing. Adding it to main.tscn is unconditional — single-
# player runs simply have an empty layer. Avoids a "spawn the layer only
# in co-op" branch in main_scene.gd.
#
# RemoteKitten reads its position each frame from the session's
# network_sync; this layer is a roster reconciler, not a render loop.

const REMOTE_KITTEN_SCENE: String = "res://scenes/remote_kitten.tscn"

# Deterministic per-slot tint so teammates stay visually distinct from
# each other and from the local kitten (placeholder color is tan/yellow).
# Indexes wrap modulo TINTS.size() — 4 slots cover MAX_PLAYERS.
const TINTS: Array[Color] = [
	Color(0.6, 0.85, 1.0, 1.0),   # blue
	Color(1.0, 0.6, 0.6, 1.0),    # red
	Color(0.6, 1.0, 0.6, 1.0),    # green
	Color(1.0, 0.85, 0.6, 1.0),   # orange
]

var _kittens: Dictionary = {}  # player_id -> RemoteKitten
var _connected_lobby: NakamaLobby = null
var _scene: PackedScene = null

func _ready() -> void:
	_scene = load(REMOTE_KITTEN_SCENE)
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	_bind_lobby(gs.lobby)
	reconcile()

func _exit_tree() -> void:
	_unbind_lobby()

# Public for testability. Reads the current GameState.lobby + coop_session
# and brings the children map in sync with the roster (skipping the local
# player_id). A null lobby or session clears all children.
func reconcile() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		_clear_all()
		_bind_lobby(null)
		return
	var session: CoopSession = gs.coop_session
	var lobby: NakamaLobby = gs.lobby
	# Re-bind if the active lobby changed since last reconcile so a
	# mid-test or mid-match lobby swap rewires the lobby_updated signal
	# instead of leaving us subscribed to the old (possibly freed) one.
	_bind_lobby(lobby)
	if lobby == null or lobby.lobby_state == null or session == null:
		_clear_all()
		return
	var sync = session.network_sync
	var local_id: String = lobby.local_player_id
	# Track desired ids so we can free anything not in the roster.
	var desired: Dictionary = {}
	var slot_index: int = 0
	for p in lobby.lobby_state.players:
		if p == null or p.player_id == "" or p.player_id == local_id:
			slot_index += 1
			continue
		desired[p.player_id] = true
		if not _kittens.has(p.player_id):
			_spawn(p, sync, slot_index)
		else:
			# Update name/tint in case a PLAYER_INFO landed mid-session.
			var existing: RemoteKitten = _kittens[p.player_id]
			existing.kitten_name = p.kitten_name
			if existing.has_node("Label"):
				existing.get_node("Label").text = p.kitten_name
		slot_index += 1
	# Free anything the roster no longer contains.
	for pid in _kittens.keys():
		if not desired.has(pid):
			var node: RemoteKitten = _kittens[pid]
			_kittens.erase(pid)
			if is_instance_valid(node):
				node.queue_free()

# Internal — used by tests via reconcile() from a fixture, but also reachable
# directly so a test can spawn against an injected lobby/session pair without
# touching the autoload.
func _spawn(player: LobbyPlayer, sync, slot_index: int) -> void:
	if _scene == null:
		_scene = load(REMOTE_KITTEN_SCENE)
	var inst: RemoteKitten = _scene.instantiate()
	inst.player_id = player.player_id
	inst.kitten_name = player.kitten_name
	inst.tint_color = TINTS[slot_index % TINTS.size()]
	inst.network_sync = sync
	add_child(inst)
	_kittens[player.player_id] = inst

func _clear_all() -> void:
	for pid in _kittens.keys():
		var node: RemoteKitten = _kittens[pid]
		if is_instance_valid(node):
			node.queue_free()
	_kittens.clear()

func _bind_lobby(new_lobby: NakamaLobby) -> void:
	if new_lobby == _connected_lobby:
		return
	_unbind_lobby()
	if new_lobby == null:
		return
	new_lobby.lobby_updated.connect(_on_lobby_updated)
	_connected_lobby = new_lobby

func _unbind_lobby() -> void:
	if _connected_lobby == null:
		return
	if _connected_lobby.lobby_updated.is_connected(_on_lobby_updated):
		_connected_lobby.lobby_updated.disconnect(_on_lobby_updated)
	_connected_lobby = null

func _on_lobby_updated(_state: LobbyState) -> void:
	reconcile()

func remote_kitten_count() -> int:
	return _kittens.size()

func remote_kitten_for(player_id: String) -> RemoteKitten:
	return _kittens.get(player_id)
