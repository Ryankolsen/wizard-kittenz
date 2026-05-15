extends GutTest

# Preloaded constant rather than the class_name reference — same Godot
# 4 class-name-resolution trap noted in #44/#49: sibling script loads
# don't always settle class_name before a test parses against it.
const QuitDungeonHandler := preload("res://scripts/dungeon/quit_dungeon_handler.gd")

# Quit-Dungeon flow (#45, PRD #42, simplified in #114). Two surfaces:
#  1. QuitDungeonHandler — pure save-vs-skip branch, no scene tree. Now
#     reads everything from GameState via SaveManager.save_from_state().
#  2. PauseMenu scene wiring — button enabled, dialog opens / cancels.
#
# The scene-change-to-character-creation half of the contract isn't
# exercised here because change_scene_to_file would tear down the
# headless test runner; the confirm wiring is covered by the handler
# tests + the dialog-visibility tests below.

func after_each():
	if FileAccess.file_exists(SaveManager.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.DEFAULT_PATH))
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_solo_quit_saves_character():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Pixel")
	c.xp = 99
	gs.current_character = c
	QuitDungeonHandler.save_and_exit(null)
	var loaded := SaveManager.load()
	assert_not_null(loaded, "save file must exist after solo quit")
	assert_eq(loaded.xp, 99, "saved XP must match character XP at quit time")

func test_solo_quit_saves_skill_tree():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	gs.current_character = c
	var tree := SkillTree.make_mage_tree()
	var first_id: String = tree.all_nodes()[0].id
	tree.unlock(first_id)
	gs.skill_tree = tree
	QuitDungeonHandler.save_and_exit(null)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_true(loaded.unlocked_skill_ids.has(first_id), "unlocked skill must persist")

# Quit-save data-gap fix (#114). Previously the handler passed null for
# cosmetic_inv so any unlocked pack vanished on quit. save_from_state()
# reads it from GameState directly.
func test_solo_quit_saves_cosmetic_inventory():
	var gs := get_node("/root/GameState")
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	gs.cosmetic_inventory.grant("starter_pack")
	QuitDungeonHandler.save_and_exit(null)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_true(loaded.cosmetic_packs.has("starter_pack"),
		"cosmetic_inventory must persist on quit")

func test_solo_quit_saves_currency_ledger():
	var gs := get_node("/root/GameState")
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	gs.currency_ledger.credit(250, CurrencyLedger.Currency.GOLD)
	QuitDungeonHandler.save_and_exit(null)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_eq(loaded.gold_balance, 250,
		"currency_ledger gold balance must persist on quit")

func test_solo_quit_saves_paid_unlocks():
	var gs := get_node("/root/GameState")
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	gs.paid_unlocks.grant("archmage")
	QuitDungeonHandler.save_and_exit(null)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_true(loaded.paid_class_unlocks.has("archmage"),
		"paid_unlocks must persist on quit")

func test_solo_quit_saves_item_inventory():
	var gs := get_node("/root/GameState")
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	gs.item_inventory.equip(ItemCatalog.find("iron_sword"))
	QuitDungeonHandler.save_and_exit(null)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	var restored := loaded.to_item_inventory()
	assert_eq(restored.equipped_in(ItemData.Slot.WEAPON).id, "iron_sword",
		"equipped item must persist on quit")

func test_solo_quit_saves_dungeon_run_state():
	var gs := get_node("/root/GameState")
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var controller := DungeonRunController.new()
	var dungeon := DungeonGenerator.generate(12345)
	controller.start(dungeon)
	controller.seed = 12345
	gs.dungeon_run_controller = controller
	QuitDungeonHandler.save_and_exit(null)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_false(loaded.dungeon_run_state.is_empty(),
		"dungeon_run_state must be non-empty after quit with active run")
	assert_eq(int(loaded.dungeon_run_state.get("seed", -1)), 12345,
		"dungeon_run_state must contain the controller seed")

func test_multiplayer_quit_skips_save():
	var gs := get_node("/root/GameState")
	gs.current_character = CharacterData.make_new(CharacterData.CharacterClass.THIEF)
	var session := CoopSession.new()
	QuitDungeonHandler.save_and_exit(session)
	assert_false(FileAccess.file_exists(SaveManager.DEFAULT_PATH),
		"multiplayer quit must not write a save file")

func test_quit_with_null_character_does_not_crash():
	var gs := get_node("/root/GameState")
	gs.current_character = null
	var ok: bool = QuitDungeonHandler.save_and_exit(null)
	assert_false(ok)
	assert_false(FileAccess.file_exists(SaveManager.DEFAULT_PATH))

# Multiplayer quit preserves the run's XP/loot in memory — the
# CharacterData instance is the source of truth and the handler
# doesn't mutate or reset it. The save-skip is what matters; this
# test pins that the in-memory state survives the call.
func test_multiplayer_quit_preserves_character_xp():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	c.xp = 42
	c.level = 3
	gs.current_character = c
	var session := CoopSession.new()
	QuitDungeonHandler.save_and_exit(session)
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

# Regression: confirm_quit_dungeon must clear GameState.current_character
# so character_creation.gd does NOT auto-bounce back to main.tscn.
# Root cause: PauseMenu called change_scene_to_file while current_character
# was still non-null, causing character_creation._ready() to skip the picker
# and immediately redirect to the dungeon — making Confirm appear to do nothing.
func test_confirm_quit_clears_game_state_character():
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		pending("GameState autoload not present — skipping")
		return
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "TestKitten")
	gs.current_character = c
	gs.skill_tree = SkillTree.make_mage_tree()
	gs.dungeon_run_controller = null
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	# confirm_quit_dungeon queues a deferred change_scene_to_file — the
	# GameState clearing happens synchronously before that, so assertions
	# here run before the deferred call fires.
	scene.confirm_quit_dungeon()
	assert_null(gs.current_character,
		"GameState.current_character must be null after confirm_quit_dungeon")
	assert_null(gs.skill_tree,
		"GameState.skill_tree must be null after confirm_quit_dungeon")
	assert_null(gs.dungeon_run_controller,
		"GameState.dungeon_run_controller must be null after confirm_quit_dungeon")
