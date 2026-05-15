extends GutTest

# Tests for NakamaLobby OP_BOSS_CLEARED, OP_REQUEST_TRANSITION, and
# OP_DUNGEON_TRANSITION_START routing (#99). Sibling of
# test_nakama_lobby_host_pause — same wire-layer-without-a-socket pattern.
# Authority checks: OP_BOSS_CLEARED + OP_DUNGEON_TRANSITION_START require
# the sender presence to match the lobby host (host-authoritative seed
# minting); OP_REQUEST_TRANSITION is acted on only by the host receiver
# (any peer can send it, but only the host responds).

func _make_lobby_with_host(host_id: String, local_id: String = "") -> NakamaLobby:
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	var host := LobbyPlayer.make(host_id, "host-kitten", "Mage", true)
	lobby.lobby_state.add_player(host)
	lobby.local_player_id = local_id if local_id != "" else host_id
	return lobby

# --- op-code distinctness ---------------------------------------------------

func test_op_codes_distinct_from_existing():
	# Pin op-code numbering so a future OP_* addition doesn't silently
	# overlap and route the wrong payload.
	var ops := [
		NakamaLobby.OP_PLAYER_INFO, NakamaLobby.OP_READY_TOGGLE,
		NakamaLobby.OP_START_MATCH, NakamaLobby.OP_POSITION,
		NakamaLobby.OP_KILL, NakamaLobby.OP_HOST_PAUSE,
		NakamaLobby.OP_HOST_UNPAUSE, NakamaLobby.OP_BOSS_CLEARED,
		NakamaLobby.OP_REQUEST_TRANSITION,
		NakamaLobby.OP_DUNGEON_TRANSITION_START,
	]
	var seen: Dictionary = {}
	for op in ops:
		assert_false(seen.has(op), "duplicate op code: %d" % op)
		seen[op] = true

# --- OP_BOSS_CLEARED routing ------------------------------------------------

func test_op_boss_cleared_emits_from_host_sender():
	# Issue #99 AC1: host's boss-cleared broadcast surfaces as
	# boss_cleared_received on every receiver. Local player is a peer here
	# so the test exercises the inbound-from-host path.
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_BOSS_CLEARED, "host-1", {})
	assert_signal_emitted(lobby, "boss_cleared_received")

func test_op_boss_cleared_rejected_from_non_host_sender():
	# Authority check: the receiver-side gate filters tampered packets so a
	# malicious / desynced peer can't trick clients into opening the door
	# before the boss is actually killed.
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	lobby.lobby_state.add_player(LobbyPlayer.make("imposter", "i", "Mage", false))
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_BOSS_CLEARED, "imposter", {})
	assert_signal_not_emitted(lobby, "boss_cleared_received")

func test_op_boss_cleared_rejected_on_empty_sender():
	var lobby := _make_lobby_with_host("host-1", "host-1")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_BOSS_CLEARED, "", {})
	assert_signal_not_emitted(lobby, "boss_cleared_received")

func test_send_boss_cleared_async_non_host_is_noop():
	# Send-side host gate parallels OP_HOST_PAUSE — a non-host calling this
	# silently no-ops without emitting locally or hitting the wire.
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	watch_signals(lobby)
	lobby.send_boss_cleared_async()
	assert_signal_not_emitted(lobby, "boss_cleared_received",
		"non-host send is a no-op")

func test_send_boss_cleared_async_host_emits_locally_without_socket():
	# Self-broadcast: host's local boss_cleared_received fires immediately so
	# its own ExitDoor opens through the same code path remote clients use.
	# Mirrors send_host_pause_async.
	var lobby := _make_lobby_with_host("host-1", "host-1")
	watch_signals(lobby)
	lobby.send_boss_cleared_async()
	assert_signal_emitted(lobby, "boss_cleared_received")

# --- OP_REQUEST_TRANSITION routing ------------------------------------------

func test_op_request_transition_emits_only_on_host_receiver():
	# Only the host acts on a peer's transition request — peer receivers
	# drop the packet because the host is the sole minting authority.
	var host_lobby := _make_lobby_with_host("host-1", "host-1")
	host_lobby.lobby_state.add_player(LobbyPlayer.make("peer-2", "p", "Mage", false))
	watch_signals(host_lobby)
	host_lobby.apply_state(NakamaLobby.OP_REQUEST_TRANSITION, "peer-2", {})
	assert_signal_emitted(host_lobby, "transition_requested_received")

func test_op_request_transition_dropped_on_peer_receiver():
	var peer_lobby := _make_lobby_with_host("host-1", "peer-2")
	peer_lobby.lobby_state.add_player(LobbyPlayer.make("peer-2", "p", "Mage", false))
	peer_lobby.lobby_state.add_player(LobbyPlayer.make("peer-3", "p", "Mage", false))
	watch_signals(peer_lobby)
	peer_lobby.apply_state(NakamaLobby.OP_REQUEST_TRANSITION, "peer-3", {})
	assert_signal_not_emitted(peer_lobby, "transition_requested_received",
		"peer ignores another peer's transition request")

func test_op_request_transition_dropped_on_empty_sender():
	var lobby := _make_lobby_with_host("host-1", "host-1")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_REQUEST_TRANSITION, "", {})
	assert_signal_not_emitted(lobby, "transition_requested_received")

# --- OP_DUNGEON_TRANSITION_START routing ------------------------------------

func test_op_dungeon_transition_emits_with_seed_from_host():
	# Issue #99 AC2: host's seed broadcast surfaces as
	# dungeon_transition_received(seed) on every receiver including the
	# host's own self-echo.
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DUNGEON_TRANSITION_START, "host-1", {"seed": 12345})
	assert_signal_emitted(lobby, "dungeon_transition_received")
	assert_signal_emitted_with_parameters(lobby, "dungeon_transition_received", [12345])

func test_op_dungeon_transition_rejected_from_non_host_sender():
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	lobby.lobby_state.add_player(LobbyPlayer.make("imposter", "i", "Mage", false))
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DUNGEON_TRANSITION_START, "imposter", {"seed": 7})
	assert_signal_not_emitted(lobby, "dungeon_transition_received")

func test_op_dungeon_transition_rejected_on_negative_seed():
	# Defensive against a future protocol bug / sign-bit corruption that
	# would route through DungeonGenerator's randomize-on-negative branch
	# and desync the party.
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DUNGEON_TRANSITION_START, "host-1", {"seed": -1})
	assert_signal_not_emitted(lobby, "dungeon_transition_received")

func test_op_dungeon_transition_rejected_on_missing_seed():
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DUNGEON_TRANSITION_START, "host-1", {})
	assert_signal_not_emitted(lobby, "dungeon_transition_received")

func test_send_dungeon_transition_async_non_host_is_noop():
	var lobby := _make_lobby_with_host("host-1", "peer-2")
	watch_signals(lobby)
	lobby.send_dungeon_transition_async(42)
	assert_signal_not_emitted(lobby, "dungeon_transition_received",
		"non-host send is a no-op")

func test_send_dungeon_transition_async_host_emits_locally():
	# Host's self-echo through the local emit drives its own
	# dungeon_transition_received → reload chain even when offline /
	# without a real socket.
	var lobby := _make_lobby_with_host("host-1", "host-1")
	watch_signals(lobby)
	lobby.send_dungeon_transition_async(42)
	assert_signal_emitted(lobby, "dungeon_transition_received")
	assert_signal_emitted_with_parameters(lobby, "dungeon_transition_received", [42])

func test_send_dungeon_transition_async_host_rejects_negative_seed():
	# Defense in depth — even on the send side, refuse to ship a negative
	# seed that would bypass DungeonGenerator's deterministic path.
	var lobby := _make_lobby_with_host("host-1", "host-1")
	watch_signals(lobby)
	lobby.send_dungeon_transition_async(-5)
	assert_signal_not_emitted(lobby, "dungeon_transition_received")
