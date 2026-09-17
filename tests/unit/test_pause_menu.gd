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

# Pause-button / per-tab tutorial group wiring (issues #605-607, PRD #596).
# Note the pause-button tip itself (topic "pause_menu") no longer
# auto-triggers from PauseMenu.open() -- it now fires from HUD before the
# menu is ever opened (see test_hud_tutorial.gd), since firing it here
# always rendered the "tap here to pause" tip over an already-open menu
# describing a button the player had already clicked. The group membership
# assertion below still lives here since HUD's PauseButton and this scene's
# tab buttons are what those tutorials actually highlight.

func _find_tutorial_overlay(scene: Node) -> Node:
	return scene.find_child("TutorialOverlay", true, false)

func test_pause_button_and_all_tabs_in_tutorial_groups():
	var hud = load("res://scenes/hud.tscn").instantiate()
	add_child_autofree(hud)
	var pause_btn: Node = hud.find_child("PauseButton", true, false)
	assert_true(pause_btn.is_in_group("tutorial_target_pause_button"),
		"HUD's PauseButton must be in tutorial_target_pause_button")

	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	var stats_tab: Node = scene.find_child("StatsTabButton", true, false)
	var skills_tab: Node = scene.find_child("SkillsTabButton", true, false)
	var inventory_tab: Node = scene.find_child("InventoryTabButton", true, false)
	var items_tab: Node = scene.find_child("ItemsTabButton", true, false)
	var achievements_tab: Node = scene.find_child("AchievementsTabButton", true, false)
	assert_true(stats_tab.is_in_group("tutorial_target_stats_tab"),
		"StatsTabButton must be in tutorial_target_stats_tab")
	assert_true(skills_tab.is_in_group("tutorial_target_skills_tab"),
		"SkillsTabButton must be in tutorial_target_skills_tab")
	assert_true(inventory_tab.is_in_group("tutorial_target_inventory_tab"),
		"InventoryTabButton must be in tutorial_target_inventory_tab")
	assert_true(items_tab.is_in_group("tutorial_target_items_tab"),
		"ItemsTabButton must be in tutorial_target_items_tab")
	assert_true(achievements_tab.is_in_group("tutorial_target_achievements_tab"),
		"AchievementsTabButton must be in tutorial_target_achievements_tab")

func test_close_after_tutorial_finished_still_unpauses():
	# Uses the stats_tab intro (rather than the old pause_menu-on-open
	# trigger, now removed) to exercise "closing after a per-tab tutorial
	# already finished still unpauses" generically.
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = []
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_stats_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay)
	overlay.skip()
	assert_false(get_tree().paused,
		"the overlay's own skip()/close() must unpause immediately")
	scene.close()
	assert_false(get_tree().paused,
		"closing the pause menu after the tutorial already finished must still leave the tree unpaused")

# inventory_tab / equip_gear tutorial auto-trigger wiring (issue #605
# follow-up, #606, PRD #596). Splitting the old monolithic pause_menu topic
# means opening the Inventory tab now shows its own intro (inventory_tab)
# before chaining into the detailed equip_gear walkthrough -- the two must
# never stack on the same frame, since equip_gear's own seen-state doesn't
# depend on inventory_tab's. pause_menu is pre-seeded as already-seen in
# these tests so only the inventory_tab / equip_gear triggers are under
# test.

func test_first_inventory_tab_open_triggers_inventory_tab_tutorial():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_null(_find_tutorial_overlay(scene),
		"opening the pause menu itself must not fire the inventory_tab tutorial")
	scene._on_inventory_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay, "the first Inventory tab open must auto-show the inventory_tab tutorial overlay")
	assert_true(overlay.visible, "the overlay must be open, not just instantiated")
	get_tree().paused = false

func test_inventory_tab_tutorial_finished_chains_into_equip_gear():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_inventory_tab_pressed()
	var intro := _find_tutorial_overlay(scene)
	assert_not_null(intro)
	intro.finished.emit("inventory_tab")
	assert_true(gs.tutorial_seen_topics.has("inventory_tab"),
		"finishing the intro overlay must mark inventory_tab seen")
	var chained := _find_tutorial_overlay(scene)
	assert_not_null(chained,
		"finishing the inventory_tab intro must chain straight into the equip_gear tutorial")
	get_tree().paused = false

func test_already_seen_inventory_tab_skips_straight_to_equip_gear():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu", "inventory_tab"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_inventory_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay, "with inventory_tab already seen, opening the tab must go straight to equip_gear")
	get_tree().paused = false

func test_already_seen_equip_gear_does_not_retrigger():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu", "inventory_tab", "equip_gear"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_inventory_tab_pressed()
	assert_null(_find_tutorial_overlay(scene),
		"once seen, opening the Inventory tab must not re-trigger the equip_gear tutorial")
	get_tree().paused = false

func test_equip_gear_tutorial_finished_marks_seen():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu", "inventory_tab"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_inventory_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay)
	overlay.finished.emit("equip_gear")
	assert_true(gs.tutorial_seen_topics.has("equip_gear"),
		"finishing the overlay must mark equip_gear seen")
	get_tree().paused = false

func test_empty_bag_falls_back_to_text_only_second_step():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu", "inventory_tab"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	gs.item_inventory = ItemInventory.new()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_inventory_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay)
	overlay.advance()
	var box := overlay.find_child("HighlightBox", true, false) as Control
	assert_false(box.visible,
		"an empty bag must fall back to a text-only bubble on the bag-item step, not crash")
	get_tree().paused = false

# stats_tab / items_tab / achievements_tab intro tutorials (issue #605
# follow-up, PRD #596). These tabs have no detailed follow-up tutorial (no
# equip_gear/assign_skills equivalent), so opening the tab shows their intro
# directly with nothing to chain into afterward.

func test_first_stats_tab_open_triggers_stats_tab_tutorial():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_stats_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay, "the first Stats tab open must auto-show the stats_tab tutorial overlay")
	get_tree().paused = false

func test_already_seen_stats_tab_does_not_retrigger():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu", "stats_tab"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_stats_tab_pressed()
	assert_null(_find_tutorial_overlay(scene),
		"once seen, opening the Stats tab must not re-trigger the stats_tab tutorial")
	get_tree().paused = false

func test_first_items_tab_open_triggers_items_tab_tutorial():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_items_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay, "the first Items tab open must auto-show the items_tab tutorial overlay")
	get_tree().paused = false

func test_already_seen_items_tab_does_not_retrigger():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu", "items_tab"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_items_tab_pressed()
	assert_null(_find_tutorial_overlay(scene),
		"once seen, opening the Items tab must not re-trigger the items_tab tutorial")
	get_tree().paused = false

func test_first_achievements_tab_open_triggers_achievements_tab_tutorial():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_achievements_tab_pressed()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay, "the first Achievements tab open must auto-show the achievements_tab tutorial overlay")
	get_tree().paused = false

func test_already_seen_achievements_tab_does_not_retrigger():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["pause_menu", "achievements_tab"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene._on_achievements_tab_pressed()
	assert_null(_find_tutorial_overlay(scene),
		"once seen, opening the Achievements tab must not re-trigger the achievements_tab tutorial")
	get_tree().paused = false

# --- open("stats") direct-to-Stats-tab entry point (issue #616) -----------
# HUD wiring for when this parameter actually gets used is a separate,
# later slice — these tests exercise open() itself only.

func test_open_stats_shows_stats_panel_and_character_submenu():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("stats")
	assert_true((scene.find_child("StatsPanel", true, false) as Control).visible,
		"open(\"stats\") must show the Stats tab panel")
	assert_true((scene.find_child("CharacterSubmenu", true, false) as Control).visible,
		"open(\"stats\") must show the Character submenu")
	get_tree().paused = false

func test_open_stats_hides_main_menu_and_other_tabs():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("stats")
	assert_false((scene.find_child("MainMenu", true, false) as Control).visible,
		"open(\"stats\") must not leave the main pause menu screen visible")
	for tab_name in ["SkillsPanel", "InventoryTab", "ItemsPanel", "AchievementsPanel"]:
		assert_false((scene.find_child(tab_name, true, false) as Control).visible,
			"open(\"stats\") must not leave the %s tab visible" % tab_name)
	get_tree().paused = false

func test_open_with_no_args_still_lands_on_main_menu():
	# Explicit regression pin for the default initial_tab == "" branch —
	# adding the parameter must not change today's no-arg behavior.
	var gs := get_node("/root/GameState")
	gs.clear()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	assert_true((scene.find_child("MainMenu", true, false) as Control).visible,
		"open() with no args must still land on the main pause menu")
	assert_false((scene.find_child("CharacterSubmenu", true, false) as Control).visible,
		"open() with no args must not show the Character submenu")
	get_tree().paused = false

func test_open_stats_does_not_leak_inventory_tab_or_its_tutorial():
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = []
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("stats")
	assert_false((scene.find_child("InventoryTab", true, false) as Control).visible,
		"open(\"stats\") must never show the Inventory tab, even transiently")
	for overlay in scene.find_children("TutorialOverlay", "", true, false):
		assert_ne(overlay._topic_id, "inventory_tab",
			"open(\"stats\") must not trigger the inventory_tab tutorial")
	get_tree().paused = false

func test_open_stats_shows_only_stats_tab_tutorial_when_unseen():
	# Isolate the inventory-tab-leak check from stats_tab's own tutorial:
	# mark stats_tab already seen so at most zero overlays should exist.
	var gs := get_node("/root/GameState")
	gs.clear()
	gs.tutorial_seen_topics = ["stats_tab"]
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Test")
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open("stats")
	assert_eq(scene.find_children("TutorialOverlay", "", true, false).size(), 0,
		"once stats_tab is seen, open(\"stats\") must not show any tutorial overlay")
	get_tree().paused = false
