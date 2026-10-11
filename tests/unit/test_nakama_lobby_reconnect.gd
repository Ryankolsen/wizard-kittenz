extends GutTest

# Tests for NakamaLobby's unexpected-disconnect detection (connection_lost)
# and the rebind_socket resume-in-place seam (#639, parent PRD #636). Sibling
# of test_nakama_lobby_dungeon_transition — same wire-layer-without-a-real-
# socket pattern, but these tests drive a FakeSocket directly through its
# `closed` / `connection_error` / `received_match_presence` /
# `received_match_state` signals since connection_lost is keyed off the
# SOCKET itself, not a decoded match-state packet.

class FakeSocket:
	extends RefCounted
	signal closed()
	signal connection_error(p_error)
	signal received_match_presence(p_match_presence_event)
	signal received_match_state(p_match_state)

	var leave_match_async_called: bool = false

	func leave_match_async(_match_id: String):
		leave_match_async_called = true
		return null

	# Stubbed because _on_match_presence re-broadcasts our own PLAYER_INFO to
	# late-joiners (nakama_lobby.gd's rebroadcast step) — any FakeSocket that
	# drives a join through received_match_presence needs this to exist.
	func send_match_state_async(_match_id: String, _op_code: int, _data: String, _presences = null):
		return null

# Builds a lobby wired to `socket` and pushes it into an "active match" state
# the same way create_async/join_async would leave it, without exercising the
# real async Nakama round-trip (NakamaService singleton calls, JSON payload
# plumbing) that create_async/join_async also perform. _match_id is the
# private seam the issue calls out as the lower-level way to reach this
# state; lobby_state / local_player_id are seeded the same way
# _seed_local_player would leave them.
func _make_active_lobby(socket: FakeSocket, local_id: String = "local-1", host_id: String = "") -> NakamaLobby:
	var lobby := NakamaLobby.new(socket, null)
	lobby.lobby_state = LobbyState.new("ABCDE")
	var resolved_host_id := host_id if host_id != "" else local_id
	var is_host := resolved_host_id == local_id
	lobby.lobby_state.add_player(LobbyPlayer.make(local_id, "local-kitten", "Mage", is_host))
	if resolved_host_id != local_id:
		lobby.lobby_state.add_player(LobbyPlayer.make(resolved_host_id, "host-kitten", "Mage", true))
	lobby.local_player_id = local_id
	lobby._match_id = "match-1"
	return lobby

# --- Core wiring: connection_lost fires on an unexpected drop ---------------

func test_connection_lost_emits_on_socket_closed_during_match():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	watch_signals(lobby)
	socket.closed.emit()
	assert_signal_emitted(lobby, "connection_lost")

func test_connection_lost_emits_on_connection_error_during_match():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	watch_signals(lobby)
	socket.connection_error.emit(null)
	assert_signal_emitted(lobby, "connection_lost")

func test_connection_lost_not_emitted_before_match_started():
	# Fresh lobby, no successful create_async/join_async yet — _match_id is
	# still "". A socket drop before any match exists isn't a mid-match
	# unexpected disconnect the orchestrator needs to react to.
	var socket := FakeSocket.new()
	var lobby := NakamaLobby.new(socket, null)
	watch_signals(lobby)
	socket.closed.emit()
	assert_signal_not_emitted(lobby, "connection_lost")

# --- rebind_socket preserves match-domain state -----------------------------

func test_rebind_socket_preserves_lobby_state_and_match_id():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var original_lobby_state := lobby.lobby_state
	var original_local_player_id := lobby.local_player_id
	var original_match_id := lobby._match_id
	var original_seed_sync := lobby.dungeon_seed_sync
	var original_pause_state := lobby.host_pause_state

	var new_socket := FakeSocket.new()
	lobby.rebind_socket(new_socket, null)

	assert_same(lobby.lobby_state, original_lobby_state,
		"lobby_state must survive a rebind by identity")
	assert_eq(lobby.local_player_id, original_local_player_id)
	assert_eq(lobby._match_id, original_match_id)
	assert_same(lobby.dungeon_seed_sync, original_seed_sync,
		"dungeon_seed_sync must survive a rebind by identity")
	assert_same(lobby.host_pause_state, original_pause_state,
		"host_pause_state must survive a rebind by identity")

func test_rebind_socket_wires_new_socket_for_match_presence():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var new_socket := FakeSocket.new()
	lobby.rebind_socket(new_socket, null)

	assert_null(lobby.lobby_state.find_player("joiner-9"))
	new_socket.received_match_presence.emit(
		{"match_id": "match-1", "joins": [{"user_id": "joiner-9", "username": "late"}], "leaves": []})
	assert_not_null(lobby.lobby_state.find_player("joiner-9"),
		"received_match_presence on the NEW socket must route through apply_joins")

# --- Edge cases --------------------------------------------------------------

func test_connection_lost_not_emitted_after_deliberate_leave():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket, "peer-2", "host-1")
	await lobby.leave_async()
	assert_true(socket.leave_match_async_called)
	assert_eq(lobby._match_id, "")
	watch_signals(lobby)
	socket.closed.emit()
	assert_signal_not_emitted(lobby, "connection_lost",
		"a deliberate leave must fully distinguish from an unexpected drop")

func test_rebind_socket_disconnects_old_socket():
	var old_socket := FakeSocket.new()
	var lobby := _make_active_lobby(old_socket)
	var new_socket := FakeSocket.new()
	lobby.rebind_socket(new_socket, null)

	old_socket.received_match_presence.emit(
		{"match_id": "match-1", "joins": [{"user_id": "ghost-9", "username": "stale"}], "leaves": []})
	assert_null(lobby.lobby_state.find_player("ghost-9"),
		"the old socket must be inert after rebind_socket")

func test_rebind_socket_does_not_emit_connection_lost():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var new_socket := FakeSocket.new()
	watch_signals(lobby)
	lobby.rebind_socket(new_socket, null)
	assert_signal_not_emitted(lobby, "connection_lost",
		"rebind_socket is a resume operation, not a drop")
