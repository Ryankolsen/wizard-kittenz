extends GutTest

# Tests for NakamaLobby OP_ATTACK routing (PRD #328 slice 4 / issue #332).
# OP_ATTACK carries the peer's attack direction (dx, dy). Sender id comes
# from the socket presence — not the payload — so a client can't spoof
# another player's swing. The receiver derives attack_type from the
# already-cached PLAYER_INFO state (character_class + equipped_weapon_id);
# no attack_type field on the wire.

func test_apply_state_op_attack_emits_attack_received():
	# Wire contract: apply_state(OP_ATTACK, sender, {dx, dy}) emits
	# attack_received with (sender_id, Vector2(dx, dy)). Matches the
	# OP_TAUNT / OP_KILL anti-spoofing model — caster is the presence,
	# not the payload.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_ATTACK, "remote_id", {"dx": 1.0, "dy": 0.0})
	assert_signal_emitted(lobby, "attack_received")
	var params: Array = get_signal_parameters(lobby, "attack_received")
	assert_eq(params[0], "remote_id", "sender_id is the presence, not from payload")
	assert_eq(params[1], Vector2(1.0, 0.0), "direction decoded from dx/dy payload")


func test_apply_state_op_attack_works_without_lobby_state():
	# In-match ATTACK packets must keep flowing after lobby_state is torn
	# down (the lobby UI may free LobbyState on match start). Mirrors the
	# OP_POSITION / OP_KILL / OP_TAUNT bypass — without this, remote
	# attacks stop animating the moment the match begins.
	var lobby := NakamaLobby.new()
	# lobby_state intentionally null
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_ATTACK, "remote_id", {"dx": 0.0, "dy": 1.0})
	assert_signal_emitted(lobby, "attack_received")


func test_apply_state_op_attack_drops_echo_of_local_player():
	# Nakama broadcasts our own send back to us. A self-echo would re-play
	# our own attack via the remote fan-out path, double-animating from
	# both Player._try_attack and the loopback. Drop at the routing layer.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_ATTACK, "me", {"dx": 1.0, "dy": 0.0})
	assert_signal_not_emitted(lobby, "attack_received",
		"echo of local player_id dropped")


func test_apply_state_op_attack_drops_packet_with_empty_sender():
	# An empty sender_id can't be attributed to a kitten — drop at the
	# routing layer rather than fanning a phantom call to CoopPlayerLayer
	# (which would no-op anyway on a missing id, but the routing guard is
	# the right place to drop it). Matches OP_KILL / OP_TAUNT pattern.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_ATTACK, "", {"dx": 1.0, "dy": 0.0})
	assert_signal_not_emitted(lobby, "attack_received")


func test_apply_state_op_attack_drops_packet_missing_dx():
	# Malformed payload (missing dx) is dropped defensively — a future
	# protocol drift shouldn't crash the render loop. Mirrors the OP_TAUNT
	# missing-enemy_id guard.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_ATTACK, "remote_id", {"dy": 1.0})
	assert_signal_not_emitted(lobby, "attack_received",
		"payload missing dx dropped silently")


func test_apply_state_op_attack_drops_packet_missing_dy():
	# Mirror of the dx guard — both keys required because Vector2(0, 0) is
	# a valid direction (in-place / stationary attack) so a missing key
	# isn't safely defaultable to 0.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_ATTACK, "remote_id", {"dx": 1.0})
	assert_signal_not_emitted(lobby, "attack_received",
		"payload missing dy dropped silently")


func test_op_attack_constant_does_not_collide_with_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to attack decoding.
	var ops := [
		NakamaLobby.OP_PLAYER_INFO, NakamaLobby.OP_READY_TOGGLE,
		NakamaLobby.OP_START_MATCH, NakamaLobby.OP_POSITION,
		NakamaLobby.OP_KILL, NakamaLobby.OP_HOST_PAUSE,
		NakamaLobby.OP_HOST_UNPAUSE, NakamaLobby.OP_BOSS_CLEARED,
		NakamaLobby.OP_REQUEST_TRANSITION,
		NakamaLobby.OP_DUNGEON_TRANSITION_START,
		NakamaLobby.OP_TAUNT, NakamaLobby.OP_HEAL,
	]
	for op in ops:
		assert_ne(NakamaLobby.OP_ATTACK, op,
			"OP_ATTACK collides with existing op code %d" % op)


func test_send_attack_async_no_socket_safe():
	# Solo path / disconnected lobby calling send_attack_async must not
	# crash. No socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_attack_async(Vector2.RIGHT)
	assert_true(true)

