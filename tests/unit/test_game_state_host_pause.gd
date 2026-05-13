extends GutTest

# Tests for GameState's host-pause scene-tree bridge (#43). When a
# NakamaLobby with a bound set_lobby() emits host_paused / host_unpaused,
# GameState flips get_tree().paused so every client freezes in lockstep
# with the host's pause press. Sibling test of test_nakama_lobby_host_pause
# (wire layer) — that one stops at the signal; this one closes the loop
# to the scene tree.

func after_each():
	# Defensive — a failing bridge could leave the tree paused and poison
	# every subsequent test's _process polling.
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func _make_host_lobby(host_id: String, local_id: String) -> NakamaLobby:
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make(host_id, "h", "Mage", true))
	lobby.local_player_id = local_id
	return lobby

func test_host_paused_signal_pauses_tree():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	assert_false(get_tree().paused, "precondition: tree not paused")
	lobby.send_host_pause_async()
	assert_true(get_tree().paused,
		"host_paused signal must pause the scene tree")

func test_host_unpaused_signal_unpauses_tree():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	lobby.send_host_pause_async()
	assert_true(get_tree().paused)
	lobby.send_host_unpause_async()
	assert_false(get_tree().paused,
		"host_unpaused signal must unpause the scene tree")

func test_remote_host_pause_packet_pauses_tree():
	# Non-host client receiving OP_HOST_PAUSE from the host — the full
	# remote path: apply_state -> _route_host_pause -> host_paused signal
	# -> GameState bridge -> get_tree().paused.
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "other-2")
	gs.set_lobby(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_true(get_tree().paused,
		"remote OP_HOST_PAUSE must pause the local tree")

func test_host_disconnect_unpauses_tree():
	# Issue spec auto-release — host leaves mid-pause, remaining clients
	# must not stay frozen forever. Bridge fires on host_unpaused which
	# apply_leaves emits when the host's id matches the leaver.
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "other-2")
	lobby.lobby_state.add_player(LobbyPlayer.make("other-2", "o", "Mage", false))
	gs.set_lobby(lobby)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_true(get_tree().paused)
	lobby.apply_leaves([{"user_id": "host-1"}])
	assert_false(get_tree().paused,
		"host-disconnect auto-release must unpause the tree")

func test_set_lobby_disconnects_previous_host_pause_signal():
	# A lobby replacement (e.g. leave + rejoin) must unbind the previous
	# lobby's signals so a stale lobby instance can't keep flipping
	# get_tree().paused after the new lobby takes over.
	var gs := get_node("/root/GameState")
	var lobby_a := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby_a)
	var lobby_b := _make_host_lobby("host-2", "host-2")
	gs.set_lobby(lobby_b)
	# Stale lobby_a still has the bound signal in its own emitter, but
	# the bridge connection should be gone now.
	assert_false(lobby_a.host_paused.is_connected(gs._on_host_paused),
		"prior lobby's host_paused must be disconnected on set_lobby")

func test_clear_unbinds_lobby_host_pause_signal():
	# GameState.clear drops the lobby ref via _disconnect_lobby_signals.
	# Same hazard as set_lobby — a leftover binding after clear would
	# leak pause flips into the next session.
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	gs.clear()
	assert_false(lobby.host_paused.is_connected(gs._on_host_paused),
		"clear must disconnect host_paused so a stale lobby can't flip tree.paused")
