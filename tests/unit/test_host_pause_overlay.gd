extends GutTest

# Tests for the non-host HostPauseOverlay (#43). The overlay listens to the
# active lobby's host_paused / host_unpaused signals through GameState and
# toggles its banner visibility. It's the surface that explains to non-host
# players why their inputs are frozen; the host has the PauseMenu's
# Unpause toggle instead, so the overlay self-suppresses on the host.

const HOST_PAUSE_OVERLAY := preload("res://scenes/host_pause_overlay.tscn")

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func _make_host_lobby(host_id: String, local_id: String) -> NakamaLobby:
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make(host_id, "h", "Mage", true))
	if local_id != host_id:
		lobby.lobby_state.add_player(LobbyPlayer.make(local_id, "o", "Thief", false))
	lobby.local_player_id = local_id
	return lobby

func test_overlay_scene_has_banner_message():
	var scene = HOST_PAUSE_OVERLAY.instantiate()
	var msg = scene.find_child("Message", true, false) as Label
	assert_not_null(msg, "overlay must have a Message Label")
	assert_eq(msg.text, "Host has paused the game")
	scene.free()

func test_overlay_hidden_by_default():
	var scene = HOST_PAUSE_OVERLAY.instantiate()
	add_child_autofree(scene)
	assert_false(scene.visible, "overlay must start hidden")

func test_overlay_process_mode_is_always():
	# The bridge in GameState pauses the tree on host_paused, so the
	# overlay must process while paused or its visibility flip wouldn't
	# render until the unpause arrived.
	var scene = HOST_PAUSE_OVERLAY.instantiate()
	assert_eq(scene.process_mode, Node.PROCESS_MODE_ALWAYS)
	scene.free()

func test_overlay_shows_on_remote_host_pause_for_non_host():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "other-2")
	gs.set_lobby(lobby)
	var scene = HOST_PAUSE_OVERLAY.instantiate()
	add_child_autofree(scene)
	# Remote host pauses the party — non-host client receives the packet.
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_true(scene.visible,
		"non-host overlay must show on remote OP_HOST_PAUSE")

func test_overlay_hides_on_unpause():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "other-2")
	gs.set_lobby(lobby)
	var scene = HOST_PAUSE_OVERLAY.instantiate()
	add_child_autofree(scene)
	lobby.apply_state(NakamaLobby.OP_HOST_PAUSE, "host-1", {})
	assert_true(scene.visible)
	lobby.apply_state(NakamaLobby.OP_HOST_UNPAUSE, "host-1", {})
	assert_false(scene.visible, "overlay must hide on remote OP_HOST_UNPAUSE")

func test_overlay_suppressed_on_host_client():
	# The host already has the PauseMenu's Unpause toggle to interact with;
	# rendering a non-dismissable "Host has paused" banner on the host's
	# own screen would be redundant and would block the toggle visually.
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	var scene = HOST_PAUSE_OVERLAY.instantiate()
	add_child_autofree(scene)
	lobby.send_host_pause_async()
	assert_false(scene.visible,
		"overlay must self-suppress on the host's own client")
