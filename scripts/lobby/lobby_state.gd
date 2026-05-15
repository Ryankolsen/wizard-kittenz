class_name LobbyState
extends RefCounted

# Pre-game lobby state: room code, joined players, per-player ready
# flags, and the start-gating rule. Pure data — no Nakama, no scene.
# When the network layer (#14, #16's online half) lands, the
# matchmaker's room-state-changed callback rebuilds this from the
# wire payload; the UI binds to the same state regardless.
#
# Capacity matches the PRD's 2-4 player co-op cap. add_player past
# MAX_PLAYERS no-ops (returns false) so the UI can surface a "lobby
# full" message without the state mutating.
const MIN_PLAYERS: int = 1
const MAX_PLAYERS: int = 4

var room_code: String = ""
var players: Array[LobbyPlayer] = []

func _init(code: String = "") -> void:
	room_code = code

func player_count() -> int:
	return players.size()

# Adds the player to the lobby. Returns true on success, false when:
# - lobby is full (>= MAX_PLAYERS)
# - the player_id is already present (rejoin should reuse existing slot,
#   not duplicate it — the wire layer's "player joined" event can fire
#   twice on flaky networks).
func add_player(player: LobbyPlayer) -> bool:
	if player == null:
		return false
	if players.size() >= MAX_PLAYERS:
		return false
	if find_player(player.player_id) != null:
		return false
	players.append(player)
	return true

# Removes by player_id. No-op on unknown id (idempotent). Returns true
# when a slot was actually removed.
func remove_player(player_id: String) -> bool:
	for i in range(players.size()):
		if players[i].player_id == player_id:
			players.remove_at(i)
			return true
	return false

func find_player(player_id: String) -> LobbyPlayer:
	for p in players:
		if p.player_id == player_id:
			return p
	return null

# Toggles ready for `player_id`. No-op on unknown id. Returns the new
# ready value (or false if not found) so the UI can update its row
# without a second lookup.
func set_ready(player_id: String, value: bool) -> bool:
	var p := find_player(player_id)
	if p == null:
		return false
	p.ready = value
	return p.ready

# Host gate: lobby can be started iff at least MIN_PLAYERS are joined
# AND every joined player is ready. The host's ready flag counts the
# same as everyone else's — there's no special "host can start without
# being ready" carve-out. Removes the "host forgot to ready up" bug.
func can_start() -> bool:
	if players.size() < MIN_PLAYERS:
		return false
	for p in players:
		if not p.ready:
			return false
	return true

func host() -> LobbyPlayer:
	for p in players:
		if p.is_host:
			return p
	return null

func to_dict() -> Dictionary:
	var arr: Array = []
	for p in players:
		arr.append(p.to_dict())
	return {
		"room_code": room_code,
		"players": arr,
	}

static func from_dict(d: Dictionary) -> LobbyState:
	var ls := LobbyState.new(String(d.get("room_code", "")))
	var arr: Array = d.get("players", [])
	for entry in arr:
		if entry is Dictionary:
			ls.players.append(LobbyPlayer.from_dict(entry))
	return ls
