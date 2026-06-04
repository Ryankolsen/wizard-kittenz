extends GutTest

# Tests for NakamaLobby OP_PLAYER_DIED routing (PRD #328 slice 8,
# issue #336). Sibling of test_nakama_lobby_player_hit.gd. Payload is
# intentionally empty — target_id is taken from the socket presence
# (the dead player broadcasts their own death; same anti-spoofing model
# as OP_KILL / OP_PLAYER_HIT).

func test_apply_state_op_player_died_emits_player_died_received():
	# Receiver decodes the empty payload and emits player_died_received
	# with target_id from sender presence.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_DIED, "remote_id", {})
	assert_signal_emitted(lobby, "player_died_received")
	var params: Array = get_signal_parameters(lobby, "player_died_received")
	assert_eq(params[0], "remote_id", "target_id from sender presence")


func test_apply_state_op_player_died_works_without_lobby_state():
	# In-match packets bypass the lobby_state == null guard.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_DIED, "remote_id", {})
	assert_signal_emitted(lobby, "player_died_received")


func test_apply_state_op_player_died_drops_empty_sender():
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_DIED, "", {})
	assert_signal_not_emitted(lobby, "player_died_received")


func test_apply_state_op_player_died_drops_echo_of_local_player():
	# Self-echo would re-trigger the local death visual a second time
	# through the remote-fan-out path. The local Player owns its own
	# death visual at the _check_died site, so the echo is dropped at
	# the routing layer.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_DIED, "me", {})
	assert_signal_not_emitted(lobby, "player_died_received",
		"self-echo dropped — local death visual already played")


func test_op_player_died_constant_distinct_from_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap.
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_PLAYER_INFO)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_READY_TOGGLE)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_START_MATCH)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_POSITION)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_KILL)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_HEAL)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_TAUNT)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_ATTACK)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_DAMAGE_DEALT)
	assert_ne(NakamaLobby.OP_PLAYER_DIED, NakamaLobby.OP_PLAYER_HIT)


func test_send_player_died_async_no_socket_safe():
	# Solo path / disconnected lobby calling send_player_died_async
	# must not crash. No socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_player_died_async()
	assert_true(true)
