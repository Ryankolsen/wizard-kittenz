extends GutTest

# Tests for NakamaLobby OP_POSITION routing added in #35. The op carries
# in-match position packets; apply_state decodes the payload and emits
# position_received for GameState to forward into the network sync manager.
# Decoupling via signal keeps NakamaLobby testable without a live
# CoopSession or Player render layer.

func test_apply_state_op_position_emits_position_received():
	# Issue acceptance criterion: apply_state(OP_POSITION, sender, {...})
	# emits position_received with the right player_id, position, timestamp.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id", {"x": 10.0, "y": 20.0, "ts": 1.5})
	assert_signal_emitted(lobby, "position_received")
	var params: Array = get_signal_parameters(lobby, "position_received")
	assert_eq(params[0], "remote_id", "player_id is the sender id")
	assert_eq(params[1], Vector2(10, 20), "position decoded from x/y keys")
	assert_eq(params[2], 1.5, "timestamp decoded from ts key")

func test_apply_state_op_position_works_without_lobby_state():
	# Position packets must continue to flow even after lobby_state is
	# torn down (the lobby UI may free the LobbyState on match start).
	# All other ops short-circuit on null lobby_state; OP_POSITION must
	# not, or remote kittens stop moving the moment the match starts.
	var lobby := NakamaLobby.new()
	# lobby_state intentionally null
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id", {"x": 5.0, "y": 6.0, "ts": 2.0})
	assert_signal_emitted(lobby, "position_received")

func test_apply_state_op_position_drops_packet_with_missing_keys():
	# Defensive: a malformed payload from a future protocol drift shouldn't
	# crash the render loop or fan a Vector2.ZERO emission downstream
	# (which would teleport the remote kitten to the origin).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id", {})
	assert_signal_not_emitted(lobby, "position_received",
		"empty payload dropped silently")
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id", {"x": 1.0, "y": 2.0})
	assert_signal_not_emitted(lobby, "position_received",
		"missing ts dropped silently")
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id", {"x": 1.0, "ts": 0.5})
	assert_signal_not_emitted(lobby, "position_received",
		"missing y dropped silently")

func test_apply_state_op_position_drops_packet_with_empty_sender():
	# An empty sender_id can't be looked up downstream and would index a
	# ghost interpolator. Drop at the routing layer.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "", {"x": 1.0, "y": 2.0, "ts": 0.5})
	assert_signal_not_emitted(lobby, "position_received")

func test_apply_state_op_position_drops_echo_of_local_player():
	# Nakama broadcasts our own send back to us; routing it would feed the
	# local player's position into the remote interpolator and double-render
	# our own kitten. Drop self-echoes at the routing layer.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "me", {"x": 1.0, "y": 2.0, "ts": 0.5})
	assert_signal_not_emitted(lobby, "position_received",
		"echo of local player_id dropped")

func test_op_position_constant_does_not_collide_with_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to position decoding.
	assert_ne(NakamaLobby.OP_POSITION, NakamaLobby.OP_PLAYER_INFO)
	assert_ne(NakamaLobby.OP_POSITION, NakamaLobby.OP_READY_TOGGLE)
	assert_ne(NakamaLobby.OP_POSITION, NakamaLobby.OP_START_MATCH)

func test_send_position_async_no_socket_safe():
	# A solo path / disconnected lobby calling send_position_async (e.g. a
	# Player that hasn't unregistered the broadcast yet) must not crash.
	# No socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_position_async(0.0, Vector2(1, 2))  # no await — coroutine returns immediately
	# No assertion — the test passes if the call doesn't crash.
	assert_true(true)
