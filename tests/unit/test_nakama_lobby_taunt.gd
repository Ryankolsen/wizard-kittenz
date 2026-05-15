extends GutTest

# Tests for NakamaLobby OP_TAUNT routing — outbound (send_taunt_async) and
# inbound (apply_state -> _route_taunt -> taunt_received signal). Sibling
# of test_nakama_lobby_kill.gd; the wire-layer pattern is shared.
#
# The signal is the seam: GameState routes taunt_received into
# RemoteTauntApplier when a session is active, but NakamaLobby itself
# stays decoupled so it can be tested without a CoopSession or a live
# SceneTree.

func test_apply_state_op_taunt_emits_taunt_received():
	# Wire contract: apply_state(OP_TAUNT, sender, {enemy_id, duration})
	# emits taunt_received with (caster_id, enemy_id, duration). caster_id
	# comes from the sender presence (not the payload) so a client can't
	# spoof another player's TAUNT — same anti-spoofing model as OP_KILL.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "remote_id", {"enemy_id": "r3_e0", "duration": 5.0})
	assert_signal_emitted(lobby, "taunt_received")
	var params: Array = get_signal_parameters(lobby, "taunt_received")
	assert_eq(params[0], "remote_id", "caster_id is the sender id, not from payload")
	assert_eq(params[1], "r3_e0", "enemy_id decoded from payload")
	assert_eq(params[2], 5.0, "duration decoded from payload")

func test_apply_state_op_taunt_works_without_lobby_state():
	# In-match TAUNT packets must keep flowing after lobby_state is torn
	# down (lobby UI may free LobbyState on match start). Mirrors the
	# OP_POSITION / OP_KILL bypass — without this, remote TAUNTs stop
	# applying the moment the match begins.
	var lobby := NakamaLobby.new()
	# lobby_state intentionally null
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "remote_id", {"enemy_id": "r3_e0", "duration": 5.0})
	assert_signal_emitted(lobby, "taunt_received")

func test_apply_state_op_taunt_drops_packet_with_missing_enemy_id():
	# Defensive: a malformed payload from a future protocol drift must
	# not crash and must not fan a phantom RemoteTauntApplier.apply call
	# with empty enemy_id (which the applier rejects anyway, but the
	# routing layer is the right place to drop it).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "remote_id", {"duration": 5.0})
	assert_signal_not_emitted(lobby, "taunt_received",
		"payload missing enemy_id dropped silently")

func test_apply_state_op_taunt_drops_packet_with_empty_enemy_id():
	# enemy_id is the addressing key downstream — without it
	# RemoteTauntApplier can't find the right Enemy. Drop at the routing
	# layer rather than emitting a signal downstream is forced to reject.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "remote_id", {"enemy_id": "", "duration": 5.0})
	assert_signal_not_emitted(lobby, "taunt_received",
		"empty enemy_id dropped silently")

func test_apply_state_op_taunt_drops_packet_with_missing_duration():
	# duration is the second required field — a missing key means the
	# packet can't carry the taunt window. Mirrors the missing-enemy_id
	# guard rather than defaulting to 0 (which the applier would reject
	# anyway, but a missing key is a malformed packet, not a "cleared
	# taunt" intent).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "remote_id", {"enemy_id": "r3_e0"})
	assert_signal_not_emitted(lobby, "taunt_received",
		"payload missing duration dropped silently")

func test_apply_state_op_taunt_drops_packet_with_non_positive_duration():
	# A non-positive duration on the wire isn't a "fresh taunt" event —
	# tick_taunt drives expiry locally, and the broadcaster's own guard
	# already rejects this shape on the sender side. The receive-side
	# guard backstops a misbehaving / forged client.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "remote_id", {"enemy_id": "r3_e0", "duration": 0.0})
	assert_signal_not_emitted(lobby, "taunt_received",
		"zero duration dropped silently")
	lobby.apply_state(NakamaLobby.OP_TAUNT, "remote_id", {"enemy_id": "r3_e0", "duration": -1.0})
	assert_signal_not_emitted(lobby, "taunt_received",
		"negative duration dropped silently")

func test_apply_state_op_taunt_drops_packet_with_empty_sender():
	# An empty sender_id can't be attributed to a caster — RemoteTauntApplier
	# would reject the empty caster_id anyway, but the routing layer drops
	# it earlier (matches OP_KILL / OP_POSITION pattern).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "", {"enemy_id": "r3_e0", "duration": 5.0})
	assert_signal_not_emitted(lobby, "taunt_received")

func test_apply_state_op_taunt_drops_echo_of_local_player():
	# Nakama broadcasts our own send back to us. A self-echo would re-stamp
	# our own taunt on the local Enemy, overwriting the local resolver's
	# already-correct taunt_target with the cross-client identity model
	# (taunt_source_id only). Drop at the routing layer — matches OP_KILL.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_TAUNT, "me", {"enemy_id": "r3_e0", "duration": 5.0})
	assert_signal_not_emitted(lobby, "taunt_received",
		"echo of local player_id dropped")

func test_op_taunt_constant_does_not_collide_with_other_ops():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to taunt decoding.
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_PLAYER_INFO)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_READY_TOGGLE)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_START_MATCH)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_POSITION)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_KILL)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_HOST_PAUSE)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_HOST_UNPAUSE)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_BOSS_CLEARED)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_REQUEST_TRANSITION)
	assert_ne(NakamaLobby.OP_TAUNT, NakamaLobby.OP_DUNGEON_TRANSITION_START)

func test_send_taunt_async_no_socket_safe():
	# A solo path / disconnected lobby calling send_taunt_async (e.g. a
	# bridge subscribed to a stale TauntBroadcaster) must not crash. No
	# socket / no match_id => silent no-op.
	var lobby := NakamaLobby.new()
	lobby.send_taunt_async("r3_e0", 5.0)  # no await — coroutine returns immediately
	assert_true(true)

func test_send_taunt_async_empty_enemy_id_safe():
	# An unkeyed / pre-spawn-layer enemy should be a defensive no-op on
	# the send side — without enemy_id the packet is undeliverable. Same
	# gate the broadcaster applies, mirrored here so a future caller that
	# bypasses the broadcaster still doesn't put a malformed packet on
	# the wire.
	var lobby := NakamaLobby.new()
	lobby.send_taunt_async("", 5.0)
	assert_true(true)

func test_send_taunt_async_non_positive_duration_safe():
	# Non-positive duration isn't a new taunt — tick_taunt drives expiry
	# locally, so an outbound packet with duration <= 0 is meaningless on
	# the wire. Mirrors the broadcaster's own guard.
	var lobby := NakamaLobby.new()
	lobby.send_taunt_async("r3_e0", 0.0)
	lobby.send_taunt_async("r3_e0", -1.0)
	assert_true(true)
