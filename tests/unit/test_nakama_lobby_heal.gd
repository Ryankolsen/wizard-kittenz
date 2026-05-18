extends GutTest

# Tests for NakamaLobby OP_HEAL routing — outbound (send_heal_async) and
# inbound (apply_state -> _route_heal -> heal_received signal). Sibling
# of test_nakama_lobby_taunt.gd / test_nakama_lobby_kill.gd; the wire-
# layer pattern is shared.
#
# The signal is the seam: GameState routes heal_received into
# RemoteHealApplier when a session is active, but NakamaLobby itself
# stays decoupled so it can be tested without a CoopSession or a live
# SceneTree.

func test_apply_state_op_heal_emits_heal_received():
	# Wire contract: apply_state(OP_HEAL, sender, {target_id, effect_kind,
	# amount, duration}) emits heal_received with all five fields.
	# caster_id comes from the sender presence — same anti-spoof model
	# as OP_KILL / OP_TAUNT.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HEAL, "remote_id", {
		"target_id": "u2",
		"effect_kind": "AOE_HEAL",
		"amount": 5,
		"duration": 0.0,
	})
	assert_signal_emitted(lobby, "heal_received")
	var params: Array = get_signal_parameters(lobby, "heal_received")
	assert_eq(params[0], "remote_id", "caster_id is the sender id, not from payload")
	assert_eq(params[1], "u2", "target_id decoded from payload")
	assert_eq(params[2], "AOE_HEAL", "effect_kind decoded from payload")
	assert_eq(params[3], 5, "amount decoded from payload")
	assert_eq(params[4], 0.0, "duration decoded from payload")

func test_apply_state_op_heal_works_without_lobby_state():
	# In-match HEAL packets must keep flowing after lobby_state is torn
	# down (lobby UI may free LobbyState on match start). Mirrors the
	# OP_POSITION / OP_KILL / OP_TAUNT bypass.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HEAL, "remote_id", {
		"target_id": "u2", "effect_kind": "SMART_HEAL", "amount": 5, "duration": 0.0,
	})
	assert_signal_emitted(lobby, "heal_received")

func test_apply_state_op_heal_drops_packet_with_missing_effect_kind():
	# A malformed payload without the routing key must not crash and
	# must not fan a phantom RemoteHealApplier.apply call.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HEAL, "remote_id", {
		"target_id": "u2", "amount": 5, "duration": 0.0,
	})
	assert_signal_not_emitted(lobby, "heal_received",
		"payload missing effect_kind dropped silently")

func test_apply_state_op_heal_drops_packet_with_empty_effect_kind():
	# Same rationale as missing key — without a dispatch key the receiver
	# can't route.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HEAL, "remote_id", {
		"target_id": "u2", "effect_kind": "", "amount": 5, "duration": 0.0,
	})
	assert_signal_not_emitted(lobby, "heal_received",
		"empty effect_kind dropped silently")

func test_apply_state_op_heal_drops_packet_with_empty_sender():
	# An empty sender_id can't be attributed to a caster — drop at the
	# routing layer (matches OP_KILL / OP_TAUNT / OP_POSITION).
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HEAL, "", {
		"target_id": "u2", "effect_kind": "AOE_HEAL", "amount": 5, "duration": 0.0,
	})
	assert_signal_not_emitted(lobby, "heal_received")

func test_apply_state_op_heal_drops_echo_of_local_player():
	# Nakama broadcasts our own send back to us. A self-echo would re-
	# apply the heal/buff on our local Player whose data the local
	# resolver already mutated — double-heal / refresh-from-latency. Drop
	# at the routing layer (matches OP_KILL / OP_TAUNT).
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HEAL, "me", {
		"target_id": "u2", "effect_kind": "AOE_HEAL", "amount": 5, "duration": 0.0,
	})
	assert_signal_not_emitted(lobby, "heal_received",
		"echo of local player_id dropped")

func test_apply_state_op_heal_allows_empty_target_id():
	# target_id == "" is the AOE/party-wide sentinel — NOT dropped here.
	# The applier fans this to every "players"-group node on the receiver.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HEAL, "remote_id", {
		"target_id": "", "effect_kind": "AOE_HEAL", "amount": 5, "duration": 0.0,
	})
	assert_signal_emitted(lobby, "heal_received")
	var params: Array = get_signal_parameters(lobby, "heal_received")
	assert_eq(params[1], "", "empty target_id preserved as AOE sentinel")

func test_op_heal_constant_does_not_collide_with_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to heal decoding.
	assert_eq(NakamaLobby.OP_HEAL, 12, "OP_HEAL pinned at 12 per issue spec")
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_PLAYER_INFO)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_READY_TOGGLE)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_START_MATCH)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_POSITION)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_KILL)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_HOST_PAUSE)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_HOST_UNPAUSE)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_BOSS_CLEARED)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_REQUEST_TRANSITION)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_DUNGEON_TRANSITION_START)
	assert_ne(NakamaLobby.OP_HEAL, NakamaLobby.OP_TAUNT)

func test_send_heal_async_no_socket_safe():
	# A solo path / disconnected lobby calling send_heal_async must not
	# crash. No socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_heal_async("u2", "AOE_HEAL", 5, 0.0)
	assert_true(true)

func test_send_heal_async_empty_effect_kind_safe():
	# Sender-side mirror of the routing guard — an unkeyed packet
	# wouldn't dispatch on the receiver anyway, and gating on the send
	# side saves bandwidth.
	var lobby := NakamaLobby.new()
	lobby.send_heal_async("u2", "", 5, 0.0)
	assert_true(true)
