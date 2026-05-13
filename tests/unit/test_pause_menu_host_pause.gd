extends GutTest

# Tests for PauseMenu's host-pause UI surface (#43 follow-up to wire layer
# in 93da634). Covers:
#   - HostPauseToggle button hidden when no lobby / not host
#   - HostPauseToggle visible + correctly-labeled when local is host
#   - Pressing the toggle routes to lobby.send_host_pause_async / unpause
#   - Label flips after a successful pause/unpause
#   - close() does NOT clear get_tree().paused when host-paused (else the
#     host opening their own pause menu would silently desync the wire)
#
# Wire-layer authority + edge-gating are pinned by
# test_nakama_lobby_host_pause.gd; the scene-tree bridge by
# test_game_state_host_pause.gd. This file covers the UI seam.

func after_each():
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

func test_pause_menu_has_host_pause_toggle_node():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var btn = scene.find_child("HostPauseToggle", true, false)
	assert_not_null(btn, "pause_menu.tscn must have a HostPauseToggle button")
	assert_true(btn is Button)
	scene.free()

func test_host_pause_toggle_hidden_when_no_lobby():
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	var btn = scene.find_child("HostPauseToggle", true, false) as Button
	assert_false(btn.visible,
		"HostPauseToggle must be hidden when no lobby is set")

func test_host_pause_toggle_hidden_when_not_host():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "other-2")
	gs.set_lobby(lobby)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	var btn = scene.find_child("HostPauseToggle", true, false) as Button
	assert_false(btn.visible,
		"HostPauseToggle must be hidden for non-host players")

func test_host_pause_toggle_visible_for_host():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	var btn = scene.find_child("HostPauseToggle", true, false) as Button
	assert_true(btn.visible, "HostPauseToggle must be visible for the host")
	assert_eq(btn.text, "Pause for everyone",
		"label must read 'Pause for everyone' when not paused")

func test_host_pause_toggle_label_flips_when_paused():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	# Force the flag without going through the wire.
	lobby.host_pause_state.set_paused(true)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	var btn = scene.find_child("HostPauseToggle", true, false) as Button
	assert_eq(btn.text, "Unpause for everyone",
		"label must read 'Unpause for everyone' when host-paused")

func test_pressing_toggle_pauses_party():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_host_pause_toggle_pressed()
	assert_true(lobby.host_pause_state.is_paused(),
		"toggle press must route through send_host_pause_async")

func test_pressing_toggle_again_unpauses():
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	lobby.host_pause_state.set_paused(true)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_host_pause_toggle_pressed()
	assert_false(lobby.host_pause_state.is_paused(),
		"second press must route through send_host_unpause_async")

func test_close_does_not_clear_tree_paused_when_host_paused():
	# Spec: the host opens their per-player PauseMenu after pressing
	# "Pause for everyone", then hits Resume. close() must NOT clear
	# get_tree().paused — that would unfreeze the host locally without
	# sending OP_HOST_UNPAUSE, desyncing from remote clients still frozen.
	var gs := get_node("/root/GameState")
	var lobby := _make_host_lobby("host-1", "host-1")
	gs.set_lobby(lobby)
	lobby.send_host_pause_async()
	assert_true(get_tree().paused, "precondition: host-pause flipped tree")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.close()
	assert_true(get_tree().paused,
		"close() must NOT clear tree.paused while host-paused")
	# Cleanup — clear() handles it via after_each, but be explicit so a
	# failure here doesn't poison neighbouring tests.
	lobby.send_host_unpause_async()

func test_close_clears_tree_paused_normally_in_solo():
	# Sanity: the close()-clears-tree contract still holds in solo.
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true(get_tree().paused)
	scene.close()
	assert_false(get_tree().paused, "solo close() must clear tree.paused")
