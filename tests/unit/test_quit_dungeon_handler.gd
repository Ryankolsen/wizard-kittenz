extends GutTest

# Preloaded constant rather than the class_name reference — same Godot
# 4 class-name-resolution trap noted in #44/#49: sibling script loads
# don't always settle class_name before a test parses against it.
const QuitDungeonHandler := preload("res://scripts/quit_dungeon_handler.gd")

# Quit-Dungeon flow (#45, PRD #42). Two surfaces:
#  1. QuitDungeonHandler — pure save-vs-skip branch, no scene tree.
#  2. PauseMenu scene wiring — button enabled, dialog opens / cancels.
#
# The scene-change-to-character-creation half of the contract isn't
# exercised here because change_scene_to_file would tear down the
# headless test runner; the confirm wiring is covered by the handler
# tests + the dialog-visibility tests below.

const TEST_SOLO_PATH := "user://test_quit_save.json"
const TEST_SKILLS_PATH := "user://test_quit_skills.json"
const TEST_MP_PATH := "user://test_mp_quit.json"
const TEST_NULL_PATH := "user://test_null.json"

func after_each():
	for p in [TEST_SOLO_PATH, TEST_SKILLS_PATH, TEST_MP_PATH, TEST_NULL_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_solo_quit_saves_character():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Pixel")
	c.xp = 99
	QuitDungeonHandler.save_and_exit(c, null, TEST_SOLO_PATH)
	var loaded := SaveManager.load(TEST_SOLO_PATH)
	assert_not_null(loaded, "save file must exist after solo quit")
	assert_eq(loaded.xp, 99, "saved XP must match character XP at quit time")

func test_solo_quit_saves_skill_tree():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var tree := SkillTree.make_mage_tree()
	var first_id: String = tree.all_nodes()[0].id
	tree.unlock(first_id)
	QuitDungeonHandler.save_and_exit(c, null, TEST_SKILLS_PATH, tree)
	var loaded := SaveManager.load(TEST_SKILLS_PATH)
	assert_not_null(loaded)
	assert_true(loaded.unlocked_skill_ids.has(first_id), "unlocked skill must persist")

func test_multiplayer_quit_skips_save():
	var c := CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	var session := CoopSession.new()
	QuitDungeonHandler.save_and_exit(c, session, TEST_MP_PATH)
	assert_false(FileAccess.file_exists(TEST_MP_PATH),
		"multiplayer quit must not write a save file")

func test_quit_with_null_character_does_not_crash():
	QuitDungeonHandler.save_and_exit(null, null, TEST_NULL_PATH)
	assert_false(FileAccess.file_exists(TEST_NULL_PATH))

# Multiplayer quit preserves the run's XP/loot in memory — the
# CharacterData instance is the source of truth and the handler
# doesn't mutate or reset it. The save-skip is what matters; this
# test pins that the in-memory state survives the call.
func test_multiplayer_quit_preserves_character_xp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	c.xp = 42
	c.level = 3
	var session := CoopSession.new()
	QuitDungeonHandler.save_and_exit(c, session, TEST_MP_PATH)
	assert_eq(c.xp, 42, "multiplayer quit must not zero the in-memory XP")
	assert_eq(c.level, 3, "multiplayer quit must not reset the level")

# Scene wiring — QuitDungeon button is enabled and the dialog exists.
func test_quit_dungeon_button_enabled():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var btn = scene.find_child("QuitDungeon", true, false) as Button
	assert_not_null(btn, "QuitDungeon button must exist")
	assert_false(btn.disabled, "QuitDungeon button must not be disabled")
	scene.free()

func test_quit_confirm_dialog_node_exists():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var dialog = scene.find_child("QuitConfirmDialog", true, false)
	assert_not_null(dialog, "QuitConfirmDialog must exist in pause_menu.tscn")
	scene.free()

func test_quit_button_opens_confirm_dialog():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.open_quit_confirm_dialog()
	var dialog = scene.find_child("QuitConfirmDialog", true, false) as Control
	assert_true(dialog.visible, "dialog must be visible after opening")
	var main = scene.find_child("MainMenu", true, false) as Control
	assert_false(main.visible, "main menu must be hidden while dialog is open")

func test_quit_cancel_returns_to_main_menu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.open_quit_confirm_dialog()
	scene.cancel_quit_confirm_dialog()
	var main = scene.find_child("MainMenu", true, false) as Control
	assert_true(main.visible, "main menu must be visible again after cancel")
	var dialog = scene.find_child("QuitConfirmDialog", true, false) as Control
	assert_false(dialog.visible, "dialog must be hidden after cancel")

# Solo wording surfaces "Save and exit" — multiplayer surfaces "Leave
# party." The Message label is mutated on open so the wording reflects
# the current GameState session at confirm time.
func test_solo_dialog_message_mentions_save():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_quit_confirm_dialog()
	var msg = scene.find_child("Message", true, false) as Label
	assert_not_null(msg)
	assert_true(msg.text.to_lower().contains("save"),
		"solo dialog message must mention save (got '%s')" % msg.text)
