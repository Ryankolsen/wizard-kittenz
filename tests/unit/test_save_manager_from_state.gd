extends GutTest

# SaveManager.save_from_state() — zero-param full save from GameState
# (issue #112 / PRD #111). Validates that the new entry point reads all
# fields directly from the GameState autoload and assembles a complete
# snapshot internally, so call sites don't need to know the 10-parameter
# tuple shape.

const TMP_PATH := "user://test_save_from_state.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
	if FileAccess.file_exists(SaveManager.DEFAULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.DEFAULT_PATH))
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func _make_character() -> CharacterData:
	var c := CharacterData.new()
	c.character_name = "Mittens"
	c.character_class = CharacterData.CharacterClass.WIZARD_KITTEN
	c.level = 3
	c.max_hp = 20
	c.hp = 18
	c.attack = 7
	c.defense = 2
	c.speed = 1.0
	return c

func test_core_wiring_writes_save_file():
	var gs := get_node("/root/GameState")
	gs.current_character = _make_character()
	var err: Error = SaveManager.save_from_state()
	assert_eq(err, OK)
	assert_true(FileAccess.file_exists(SaveManager.DEFAULT_PATH))

func test_all_fields_round_trip():
	var gs := get_node("/root/GameState")
	gs.current_character = _make_character()
	gs.skill_tree = gs._build_tree_for(gs.current_character)
	# Unlock the first node in the mage tree so the round-trip has a
	# non-empty unlocked_skill_ids list to assert on.
	var first_id: String = gs.skill_tree.nodes[0].id
	gs.skill_tree.unlock(first_id)

	gs.currency_ledger.credit(250, CurrencyLedger.Currency.GOLD)
	gs.cosmetic_inventory.grant("starter_pack")
	gs.paid_unlocks.grant("wizard_cat")
	gs.skill_inventory.grant("fireball")
	gs.item_inventory.equip(ItemCatalog.find("iron_sword"))

	var controller := DungeonRunController.new()
	var dungeon := DungeonGenerator.generate(12345)
	controller.start(dungeon)
	controller.seed = 12345
	gs.dungeon_run_controller = controller

	var err: Error = SaveManager.save_from_state()
	assert_eq(err, OK)

	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_true(loaded.unlocked_skill_ids.has(first_id),
		"unlocked_skill_ids should contain the unlocked node")
	assert_true(loaded.cosmetic_packs.has("starter_pack"))
	assert_true(loaded.paid_class_unlocks.has("wizard_cat"))
	assert_eq(loaded.gold_balance, 250)
	assert_true(loaded.skill_unlocks.has("fireball"))
	var restored_inv := loaded.to_item_inventory()
	assert_eq(restored_inv.equipped_in(ItemData.Slot.WEAPON).id, "iron_sword")
	assert_false(loaded.dungeon_run_state.is_empty(),
		"dungeon_run_state should be non-empty when controller is set")
	assert_eq(int(loaded.dungeon_run_state.get("seed", -1)), 12345)

func test_null_character_returns_error_without_writing():
	var gs := get_node("/root/GameState")
	gs.current_character = null
	var err: Error = SaveManager.save_from_state()
	assert_eq(err, ERR_INVALID_PARAMETER)
	assert_false(FileAccess.file_exists(SaveManager.DEFAULT_PATH),
		"no save file should be written when character is null")

func test_null_dungeon_run_controller_serializes_empty_run_state():
	var gs := get_node("/root/GameState")
	gs.current_character = _make_character()
	gs.dungeon_run_controller = null
	var err: Error = SaveManager.save_from_state()
	assert_eq(err, OK)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_true(loaded.dungeon_run_state.is_empty(),
		"empty dict expected when no controller is active")

func test_skill_inventory_is_persisted():
	# Issue #113: Player.gd kill-save call sites previously passed null for
	# skill_inventory, dropping unlocked skills on every kill. save_from_state()
	# reads it from GameState directly — assert the round trip.
	var gs := get_node("/root/GameState")
	gs.current_character = _make_character()
	gs.skill_inventory.grant("fireball")
	var err: Error = SaveManager.save_from_state()
	assert_eq(err, OK)
	var loaded := SaveManager.load()
	assert_not_null(loaded)
	assert_true(loaded.skill_unlocks.has("fireball"),
		"skill_inventory should be persisted by save_from_state")

func test_null_skill_inventory_does_not_crash():
	var gs := get_node("/root/GameState")
	gs.current_character = _make_character()
	gs.skill_inventory = null
	var err: Error = SaveManager.save_from_state()
	assert_eq(err, OK)
	assert_true(FileAccess.file_exists(SaveManager.DEFAULT_PATH))
