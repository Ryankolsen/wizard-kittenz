extends GutTest

# Tests for NakamaLobby OP_HOST_PAUSE / OP_HOST_UNPAUSE routing (#43).
# Distinct from the per-player soft-pause in #42 — this is the host-initiated
# party-wide pause. Authority check on both send (is_local_host) and receive
# (sender_id == lobby.host.player_id) sides so a misbehaving / tampered
# client can't desync the party.
#
# Sibling of test_nakama_lobby_kill / test_nakama_lobby_position; the
# wire-layer-without-a-socket pattern is shared.

func _make_lobby_with_host(host_id: String, local_id: String = "") -> NakamaLobby:
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	var host := LobbyPlayer.make(host_id, "host-kitten", "Mage", true)
	lobby.lobby_state.add_player(host)
	lobby.local_player_id = local_id if local_id != "" else host_id
	return lobby

func test_op_codes_distinct():
	# Pin the op-code numbering so a future OP_* addition can't silently
	# overlap and route the wrong payload to host-pause decoding.
	assert_ne(NakamaLobby.OP_HOST_PAUSE, NakamaLobby.OP_HOST_UNPAUSE)
	assert_ne(NakamaLobby.OP_HOST_PAUSE, NakamaLobby.OP_KILL)
	assert_ne(NakamaLobby.OP_HOST_PAUSE, NakamaLobby.OP_POSITION)
	assert_ne(NakamaLobby.OP_HOST_PAUSE, NakamaLobby.OP_START_MATCH)
	assert_ne(NakamaLobby.OP_HOST_UNPAUSE, NakamaLobby.OP_KILL)

func test_is_local_host_true_when_local_is_host():
	var lobby := _make_lobby_with_host("host-1", "host-1")
	assert_true(lobby.is_local_host())

func test_is_local_host_false_when_local_is_not_host():
	var lobby := _make_lobby_with_host("host-1", "other-2")
	assert_false(lobby.is_local_host())

func test_is_local_host_false_on_null_lobby_state():
	var lobby := NakamaLobby.new()
	# No lobby_state — pre-create_async / post-leave_async.
	assert_false(lobby.is_local_host(),
		"null lobby_state never grants pause authority")

func test_apply_state_op_host_pause_emits_host_paused_from_host_sender():
	var lobby := _make_lobby_with_host("host-1", "other-2")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_signal_emitted(lobby, "host_paused")
	assert_true(lobby.host_pause_state.is_paused())

func test_apply_state_op_host_pause_rejected_from_non_host_sender():
	# Authority check: a misbehaving / tampered client sending OP_HOST_PAUSE
	# while not being the lobby's host must be dropped. The send-side
	# is_local_host() guard already prevents legit clients from sending
	# this, but the receive-side check is the security boundary.
	var lobby := _make_lobby_with_host("host-1", "other-2")
	lobby.lobby_state.add_player(LobbyPlayer.make("imposter", "i", "Mage", false))
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "imposter", {})
	assert_signal_not_emitted(lobby, "host_paused",
		"non-host sender dropped silently")
	assert_false(lobby.host_pause_state.is_paused())

func test_apply_state_op_host_pause_rejected_on_empty_sender():
	# Defensive against a future presence-strip — an empty sender_id can't
	# be matched against a host id.
	var lobby := _make_lobby_with_host("host-1", "host-1")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "", {})
	assert_signal_not_emitted(lobby, "host_paused")

func test_apply_state_op_host_pause_rejected_on_null_lobby_state():
	# Distinct from OP_KILL / OP_POSITION which bypass the null-lobby
	# guard — host-pause needs lobby_state.host() to do the authority
	# check, so a null lobby_state is a hard drop.
	var lobby := NakamaLobby.new()
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_signal_not_emitted(lobby, "host_paused")

func test_apply_state_op_host_unpause_emits_host_unpaused():
	var lobby := _make_lobby_with_host("host-1", "other-2")
	# Put it in the paused state so the unpause edge is real.
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_UNPAUSE, "host-1", {})
	assert_signal_emitted(lobby, "host_unpaused")
	assert_false(lobby.host_pause_state.is_paused())

func test_duplicate_op_host_pause_does_not_re_emit():
	# Flaky network double-delivering OP_HOST_PAUSE — the HostPauseState
	# edge gate suppresses the second emit so downstream consumers
	# (overlay show / get_tree().paused) don't churn.
	var lobby := _make_lobby_with_host("host-1", "other-2")
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_signal_not_emitted(lobby, "host_paused",
		"duplicate pause packet suppressed by edge gate")

func test_send_host_pause_async_non_host_is_noop():
	# Bandwidth + parallels OP_KILL pattern: the send-side host gate keeps
	# a non-host client from spamming the wire. Receiving clients would
	# drop it anyway, but cheaper to never send it.
	var lobby := _make_lobby_with_host("host-1", "other-2")
	# local is NOT host.
	watch_signals(lobby)
	lobby.send_host_pause_async()
	assert_signal_not_emitted(lobby, "host_paused")
	assert_false(lobby.host_pause_state.is_paused())

func test_send_host_pause_async_host_emits_locally_without_socket():
	# Self-broadcast: even without a real socket, the host's local
	# host_paused signal must fire so the host's own scene tree freezes
	# in lockstep with what remote clients will see when their packet
	# arrives. Mirrors the "local first, then wire" pattern used by
	# send_ready_async.
	var lobby := _make_lobby_with_host("host-1", "host-1")
	watch_signals(lobby)
	lobby.send_host_pause_async()
	assert_signal_emitted(lobby, "host_paused")
	assert_true(lobby.host_pause_state.is_paused())

func test_send_host_unpause_async_host_emits_locally():
	var lobby := _make_lobby_with_host("host-1", "host-1")
	lobby.send_host_pause_async()
	watch_signals(lobby)
	lobby.send_host_unpause_async()
	assert_signal_emitted(lobby, "host_unpaused")
	assert_false(lobby.host_pause_state.is_paused())

func test_host_disconnect_auto_releases_pause():
	# Issue spec: "if the host disconnects while paused, the pause is
	# released automatically." apply_leaves snapshots the host id before
	# remove_player so it can detect that the leaver WAS the host.
	var lobby := _make_lobby_with_host("host-1", "other-2")
	lobby.lobby_state.add_player(LobbyPlayer.make("other-2", "o", "Mage", false))
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_true(lobby.host_pause_state.is_paused())
	watch_signals(lobby)
	lobby.apply_leaves([{"user_id": "host-1"}])
	assert_signal_emitted(lobby, "host_unpaused",
		"host-disconnect releases the pause")
	assert_false(lobby.host_pause_state.is_paused())

func test_non_host_disconnect_does_not_release_pause():
	# Only the host's leave triggers auto-release — a remote non-host
	# dropping mid-pause should NOT unfreeze the party.
	var lobby := _make_lobby_with_host("host-1", "host-1")
	lobby.lobby_state.add_player(LobbyPlayer.make("other-2", "o", "Mage", false))
	lobby.send_host_pause_async()
	watch_signals(lobby)
	lobby.apply_leaves([{"user_id": "other-2"}])
	assert_signal_not_emitted(lobby, "host_unpaused",
		"non-host leave does not release pause")
	assert_true(lobby.host_pause_state.is_paused())
