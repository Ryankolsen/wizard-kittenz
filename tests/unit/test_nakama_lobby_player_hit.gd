extends GutTest

# Tests for NakamaLobby OP_PLAYER_HIT routing (PRD #328 slice 7,
# issue #335). Sibling of test_nakama_lobby_damage.gd; the wire-layer
# pattern is shared. The signal is the seam: CoopPlayerLayer subscribes
# to player_hit_received and fans through to the matching RemoteKitten's
# apply_hit_reaction, but NakamaLobby itself stays decoupled so it can
# be tested without a SceneTree.

func _payload(damage: int = 8, sx: float = 100.0, sy: float = 50.0) -> Dictionary:
	return {"damage": damage, "source_x": sx, "source_y": sy}


func test_apply_state_op_player_hit_emits_player_hit_received():
	# Receiver decodes the payload and emits player_hit_received with
	# target_id from the sender presence (not from the payload, anti-
	# spoofing — the hit player broadcasts their own hit).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "remote_id", _payload(8, 100.0, 50.0))
	assert_signal_emitted(lobby, "player_hit_received")
	var params: Array = get_signal_parameters(lobby, "player_hit_received")
	assert_eq(params[0], "remote_id", "target_id from sender presence")
	assert_eq(params[1], 8, "damage decoded from payload")
	assert_eq(params[2], Vector2(100.0, 50.0), "source_position decoded")


func test_apply_state_op_player_hit_works_without_lobby_state():
	# In-match packets must keep flowing after lobby_state is torn down
	# (the lobby UI may free LobbyState on match start). Same shape as
	# OP_KILL / OP_DAMAGE_DEALT — in-match packets bypass the
	# lobby_state == null guard.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "remote_id", _payload())
	assert_signal_emitted(lobby, "player_hit_received")


func test_apply_state_op_player_hit_drops_missing_damage():
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "remote_id", {"source_x": 1.0, "source_y": 2.0})
	assert_signal_not_emitted(lobby, "player_hit_received",
		"payload missing damage dropped silently")


func test_apply_state_op_player_hit_drops_missing_source_coords():
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "remote_id", {"damage": 5, "source_x": 1.0})
	assert_signal_not_emitted(lobby, "player_hit_received",
		"missing source_y dropped silently")
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "remote_id", {"damage": 5, "source_y": 2.0})
	assert_signal_not_emitted(lobby, "player_hit_received",
		"missing source_x dropped silently")


func test_apply_state_op_player_hit_drops_non_positive_damage():
	# A "Miss" / zero-damage pulse has no reaction worth rendering.
	# Send guard already drops it; receive guard pins the contract.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "remote_id", _payload(0))
	assert_signal_not_emitted(lobby, "player_hit_received")
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "remote_id", _payload(-3))
	assert_signal_not_emitted(lobby, "player_hit_received")


func test_apply_state_op_player_hit_drops_empty_sender():
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "", _payload())
	assert_signal_not_emitted(lobby, "player_hit_received")


func test_apply_state_op_player_hit_drops_echo_of_local_player():
	# Self-echo would re-render the local Player's reaction a second time
	# from the wire. The local damage-application site already played the
	# flash + knockback, so this echo is dropped.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_PLAYER_HIT, "me", _payload())
	assert_signal_not_emitted(lobby, "player_hit_received",
		"self-echo dropped — local reaction already played")


func test_op_player_hit_constant_distinct_from_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to player-hit decoding.
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_PLAYER_INFO)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_READY_TOGGLE)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_START_MATCH)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_POSITION)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_KILL)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_HEAL)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_TAUNT)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_ATTACK)
	assert_ne(NakamaLobby.OP_PLAYER_HIT, NakamaLobby.OP_DAMAGE_DEALT)


func test_send_player_hit_async_no_socket_safe():
	# Solo path / disconnected lobby calling send_player_hit_async
	# must not crash. No socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_player_hit_async(5, Vector2(10, 20))
	assert_true(true)


func test_send_player_hit_async_non_positive_damage_safe():
	# Defensive: a "Miss" pulse at the send site is dropped before the
	# wire serializer runs. Matches the OP_DAMAGE_DEALT send-side gate.
	var lobby := NakamaLobby.new()
	lobby.send_player_hit_async(0, Vector2.ZERO)
	lobby.send_player_hit_async(-2, Vector2.ZERO)
	assert_true(true)
