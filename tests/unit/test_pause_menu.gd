extends GutTest

# Walking skeleton for the PauseMenu (#44, parent PRD #42). The menu is a
# CanvasLayer overlay opened from the HUD's Pause button. Branch:
#   - solo (GameState.coop_session == null / inactive): freeze tree
#   - multiplayer (active CoopSession): show overlay only, tree stays live
#
# These tests pin the contract — they don't exercise submenus (#47–#50)
# or quit-dungeon save/resume (#45, #46). Those land in follow-up issues.

func after_each():
	# Defensive — a failing open() in solo mode could leave the tree paused
	# and poison every subsequent test that polls _process.
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_pause_menu_scene_has_resume_button():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var btn = scene.find_child("Resume", true, false)
	assert_not_null(btn, "pause_menu.tscn must have a node named Resume")
	scene.free()

func test_open_pauses_tree_in_solo_mode():
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true(get_tree().paused, "solo open must pause the scene tree")
	get_tree().paused = false

func test_resume_unpauses_tree():
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.close()
	assert_false(get_tree().paused, "close must unpause the scene tree")

func test_is_multiplayer_false_when_coop_session_null():
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	assert_false(scene.is_multiplayer(),
		"is_multiplayer() must be false when coop_session is null")

func test_pause_menu_process_mode_is_always():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	assert_eq(scene.process_mode, Node.PROCESS_MODE_ALWAYS,
		"PauseMenu must process while tree is paused")
	scene.free()

func test_open_makes_menu_visible():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true(scene.visible, "open() must show the overlay")
	get_tree().paused = false

func test_close_hides_menu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.close()
	assert_false(scene.visible, "close() must hide the overlay")

func test_open_hides_touch_controls_and_close_restores():
	# Regression for the mobile bug where the touch overlay (same CanvasLayer
	# as the menu) sat on top of the Stats-tab "+" buttons and swallowed taps.
	# open() must hide every node in the "touch_controls" group; close() restores.
	var gs := get_node("/root/GameState")
	gs.clear()
	var fake := _FakeTouchControls.new()
	add_child_autofree(fake)
	fake.add_to_group("touch_controls")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_eq(fake.last_menu_open, true, "open() must tell touch controls the menu is open")
	scene.close()
	assert_eq(fake.last_menu_open, false, "close() must tell touch controls the menu is closed")

class _FakeTouchControls extends Node:
	var last_menu_open = null
	func set_menu_open(menu_open: bool) -> void:
		last_menu_open = menu_open

func test_hud_has_pause_button():
	var hud = load("res://scenes/hud.tscn").instantiate()
	var btn = hud.find_child("PauseButton", true, false)
	assert_not_null(btn, "HUD must expose a PauseButton during dungeon runs")
	assert_true(btn is Button, "PauseButton must be a Button")
	hud.free()

# --- Music pause/resume wiring (#488, parent PRD #485) ---------------------

func _make_lobby(player_specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
		var lp := LobbyPlayer.make(spec[0], spec[1], spec[2], false)
		ls.add_player(lp)
	return ls

func _make_character(klass: int, level: int) -> CharacterData:
	var c := CharacterData.make_new(klass, "k%d" % level)
	c.level = level
	c.max_hp = CharacterData.base_max_hp_for(klass, level)
	c.hp = c.max_hp
	c.attack = CharacterData.base_attack_for(klass, level)
	c.defense = CharacterData.base_defense_for(klass, level)
	c.speed = CharacterData.base_speed_for(klass, level)
	return c

func _make_two_room_dungeon() -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	d.add_room(start)
	d.start_id = 0
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	d.add_room(boss)
	d.boss_id = 1
	return d

func _music_player() -> AudioStreamPlayer:
	var manager := get_node_or_null("/root/MusicManager")
	assert_not_null(manager, "MusicManager autoload must be registered")
	return manager.find_child("MusicPlayer", false, false) as AudioStreamPlayer

func test_open_pauses_music_in_solo_mode():
	var gs := get_node("/root/GameState")
	gs.clear()
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true(_music_player().stream_paused, "open() must pause music in solo mode")
	get_tree().paused = false

func test_close_resumes_music():
	var gs := get_node("/root/GameState")
	gs.clear()
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.close()
	assert_false(_music_player().stream_paused, "close() must resume music")

func test_open_pauses_music_in_coop_mode():
	var gs := get_node("/root/GameState")
	gs.clear()
	var lobby := _make_lobby([["u1", "Whiskers", "Mage"]])
	var c := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 5)
	var session := CoopSession.new(lobby, {"u1": c})
	assert_true(session.start(_make_two_room_dungeon()), "session must start")
	gs.coop_session = session
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	assert_true(scene.is_multiplayer(), "scene must report multiplayer with active coop_session")
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	scene.open()
	assert_true(_music_player().stream_paused,
		"open() must pause music in co-op personal pause")
	assert_false(get_tree().paused,
		"co-op personal pause must not touch get_tree().paused")

func test_open_for_dungeon_transition_pauses_music():
	var gs := get_node("/root/GameState")
	gs.clear()
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_for_dungeon_transition()
	assert_true(_music_player().stream_paused,
		"open_for_dungeon_transition() must pause music")
	get_tree().paused = false

func test_transition_continue_resumes_music():
	var gs := get_node("/root/GameState")
	gs.clear()
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_for_dungeon_transition()
	scene._on_transition_continue_pressed()
	assert_false(_music_player().stream_paused,
		"_on_transition_continue_pressed() must resume music")

func test_close_via_transition_mode_back_button_resumes_music():
	var gs := get_node("/root/GameState")
	gs.clear()
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_for_dungeon_transition()
	scene.close()
	assert_false(_music_player().stream_paused,
		"close() during transition mode (Back button) must resume music")

func test_open_close_music_toggle_survives_repeated_cycles():
	var gs := get_node("/root/GameState")
	gs.clear()
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	for i in range(3):
		scene.open()
		scene.close()
	assert_false(_music_player().stream_paused,
		"repeated open/close cycles must leave music resumed")

func test_pause_menu_music_state_independent_of_tree_pause():
	var gs := get_node("/root/GameState")
	gs.clear()
	var lobby := _make_lobby([["u1", "Whiskers", "Mage"]])
	var c := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 5)
	var session := CoopSession.new(lobby, {"u1": c})
	assert_true(session.start(_make_two_room_dungeon()), "session must start")
	gs.coop_session = session
	var manager := get_node_or_null("/root/MusicManager")
	manager.play_music()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true(_music_player().stream_paused,
		"co-op open() must pause music even though the tree never pauses")
	assert_false(get_tree().paused,
		"co-op personal pause must never set get_tree().paused")
