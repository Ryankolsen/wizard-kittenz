extends GutTest

# Tests for NakamaLobby OP_DAMAGE_DEALT routing (PRD #328 slice 6,
# issue #334). Sibling of test_nakama_lobby_kill.gd; the wire-layer
# pattern is shared. The signal is the seam: GameState routes
# damage_received into RemoteDamageVisualizer when a session is
# active, but NakamaLobby itself stays decoupled so it can be tested
# without a SceneTree.

func test_apply_state_op_damage_dealt_emits_damage_received():
	# Receiver decodes the payload and emits damage_received with the
	# sender-presence attacker_id (not from the payload, anti-spoofing).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "remote_id", {"enemy_id": "e7", "damage": 12})
	assert_signal_emitted(lobby, "damage_received")
	var params: Array = get_signal_parameters(lobby, "damage_received")
	assert_eq(params[0], "remote_id", "attacker_id from sender presence")
	assert_eq(params[1], "e7", "enemy_id decoded from payload")
	assert_eq(params[2], 12, "damage decoded from payload")

func test_apply_state_op_damage_dealt_works_without_lobby_state():
	# Damage packets must keep flowing after lobby_state is torn down
	# (the lobby UI may free LobbyState on match start). Same shape as
	# OP_KILL — in-match packets bypass the lobby_state == null guard.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "remote_id", {"enemy_id": "e7", "damage": 5})
	assert_signal_emitted(lobby, "damage_received")

func test_apply_state_op_damage_dealt_drops_missing_enemy_id():
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "remote_id", {"damage": 5})
	assert_signal_not_emitted(lobby, "damage_received",
		"payload missing enemy_id dropped silently")

func test_apply_state_op_damage_dealt_drops_empty_enemy_id():
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "remote_id", {"enemy_id": "", "damage": 5})
	assert_signal_not_emitted(lobby, "damage_received",
		"empty enemy_id dropped silently — no scene-tree key to route on")

func test_apply_state_op_damage_dealt_drops_non_positive_damage():
	# A "Miss" / zero-damage pulse has no number worth rendering. Send
	# guard already drops it; receive guard pins the contract.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "remote_id", {"enemy_id": "e7", "damage": 0})
	assert_signal_not_emitted(lobby, "damage_received")
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "remote_id", {"enemy_id": "e7", "damage": -3})
	assert_signal_not_emitted(lobby, "damage_received")

func test_apply_state_op_damage_dealt_drops_empty_sender():
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "", {"enemy_id": "e7", "damage": 5})
	assert_signal_not_emitted(lobby, "damage_received")

func test_apply_state_op_damage_dealt_drops_echo_of_local_player():
	# Self-echo would re-render the local hit number a second time
	# above the local hit overlay, double-labeling every hit.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_DAMAGE_DEALT, "me", {"enemy_id": "e7", "damage": 5})
	assert_signal_not_emitted(lobby, "damage_received",
		"self-echo dropped — local damage path already spawned the number")

func test_op_damage_dealt_constant_distinct_from_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to damage decoding.
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_PLAYER_INFO)
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_READY_TOGGLE)
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_START_MATCH)
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_POSITION)
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_KILL)
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_HEAL)
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_TAUNT)
	assert_ne(NakamaLobby.OP_DAMAGE_DEALT, NakamaLobby.OP_ATTACK)

func test_send_damage_dealt_async_no_socket_safe():
	# Solo path / disconnected lobby calling send_damage_dealt_async
	# must not crash. No socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_damage_dealt_async("e7", 5)  # no await — coroutine returns immediately
	assert_true(true)

func test_send_damage_dealt_async_empty_enemy_id_safe():
	# Pre-spawn-layer / test fixture enemy with empty id is a defensive
	# no-op — matches the OP_KILL send-side gate.
	var lobby := NakamaLobby.new()
	lobby.send_damage_dealt_async("", 5)
	assert_true(true)
