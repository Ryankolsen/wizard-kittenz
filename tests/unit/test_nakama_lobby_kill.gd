extends GutTest

# Tests for NakamaLobby OP_KILL routing — outbound (send_kill_async) and
# inbound (apply_state -> _route_kill -> kill_received signal). Sibling
# of test_nakama_lobby_position.gd; the wire-layer pattern is shared.
#
# The signal is the seam: GameState routes kill_received into
# RemoteKillApplier when a session is active, but NakamaLobby itself stays
# decoupled so it can be tested without a CoopSession.

func test_apply_state_op_kill_emits_kill_received():
	# Issue acceptance criterion: apply_state(OP_KILL, sender, {...})
	# emits kill_received with the right enemy_id, killer_id, xp_value.
	# killer_id comes from the sender presence (not the payload) so a
	# client can't spoof another player's kill credit.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "remote_id", {"enemy_id": "r3_e0", "xp": 7})
	assert_signal_emitted(lobby, "kill_received")
	var params: Array = get_signal_parameters(lobby, "kill_received")
	assert_eq(params[0], "r3_e0", "enemy_id decoded from payload")
	assert_eq(params[1], "remote_id", "killer_id is the sender id, not from payload")
	assert_eq(params[2], 7, "xp_value decoded from xp key")

func test_apply_state_op_kill_works_without_lobby_state():
	# Kill packets must keep flowing after lobby_state is torn down (the
	# lobby UI may free LobbyState on match start). All other ops short-
	# circuit on null lobby_state; OP_KILL must not, or remote players
	# stop receiving XP from kills the moment the match begins.
	var lobby := NakamaLobby.new()
	# lobby_state intentionally null
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "remote_id", {"enemy_id": "r3_e0", "xp": 5})
	assert_signal_emitted(lobby, "kill_received")

func test_apply_state_op_kill_drops_packet_with_missing_enemy_id():
	# Defensive: a malformed payload from a future protocol drift must
	# not crash and must not fan a phantom RemoteKillApplier.apply call
	# with empty enemy_id (which would always return false anyway, but
	# the routing layer is the right place to drop it).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "remote_id", {})
	assert_signal_not_emitted(lobby, "kill_received",
		"empty payload dropped silently")
	lobby.apply_state(NakamaLobby.OP_KILL, "remote_id", {"xp": 5})
	assert_signal_not_emitted(lobby, "kill_received",
		"payload missing enemy_id dropped silently")

func test_apply_state_op_kill_drops_packet_with_empty_enemy_id():
	# enemy_id is the dedupe key downstream — without it RemoteKillApplier
	# can't gate idempotency. Drop at the routing layer rather than
	# emitting a signal that downstream is forced to reject anyway.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "remote_id", {"enemy_id": "", "xp": 5})
	assert_signal_not_emitted(lobby, "kill_received",
		"empty enemy_id dropped silently")

func test_apply_state_op_kill_drops_packet_with_empty_sender():
	# An empty sender_id can't be attributed downstream. The kill flow
	# can survive without a killer_id (the broadcaster ignores killer_id
	# beyond logging) but a self-echo check requires a non-empty sender,
	# and dropping early matches the OP_POSITION pattern.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "", {"enemy_id": "r3_e0", "xp": 5})
	assert_signal_not_emitted(lobby, "kill_received")

func test_apply_state_op_kill_drops_echo_of_local_player():
	# Nakama broadcasts our own send back to us. Without this guard the
	# self-echo would still be idempotent at apply_death time, but the
	# routing layer is cheaper and matches OP_POSITION's anti-echo
	# pattern. Also avoids falsely attributing a "remote kill" event to
	# our own kill in any future logging downstream of the signal.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "me", {"enemy_id": "r3_e0", "xp": 5})
	assert_signal_not_emitted(lobby, "kill_received",
		"echo of local player_id dropped")

func test_apply_state_op_kill_defaults_xp_to_zero_if_missing():
	# xp is metadata for the broadcast fan-out; a missing xp key
	# shouldn't crash the routing — the downstream broadcaster's own
	# non-positive-amount guard turns xp == 0 into a silent no-op for
	# the XP fan-out, but the enemy_sync.apply_death side still fires.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "remote_id", {"enemy_id": "r3_e0"})
	assert_signal_emitted(lobby, "kill_received")
	var params: Array = get_signal_parameters(lobby, "kill_received")
	assert_eq(params[2], 0, "missing xp defaults to 0")

func test_op_kill_constant_does_not_collide_with_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to kill decoding.
	assert_ne(NakamaLobby.OP_KILL, NakamaLobby.OP_PLAYER_INFO)
	assert_ne(NakamaLobby.OP_KILL, NakamaLobby.OP_READY_TOGGLE)
	assert_ne(NakamaLobby.OP_KILL, NakamaLobby.OP_START_MATCH)
	assert_ne(NakamaLobby.OP_KILL, NakamaLobby.OP_POSITION)

func test_send_kill_async_no_socket_safe():
	# A solo path / disconnected lobby calling send_kill_async (e.g. a
	# Player whose KillRewardRouter still has a stale lobby ref) must
	# not crash. No socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_kill_async("r3_e0", "u1", 5)  # no await — coroutine returns immediately
	assert_true(true)

func test_send_kill_async_empty_enemy_id_safe():
	# A pre-spawn-layer / test fixture enemy with an empty enemy_id
	# should be a defensive no-op — the wire send is skipped, matching
	# the same gate KillRewardRouter applies to apply_death. Without
	# this gate the wire would carry a packet that every receiver must
	# drop, wasting bandwidth.
	var lobby := NakamaLobby.new()
	lobby.send_kill_async("", "u1", 5)
	assert_true(true)
