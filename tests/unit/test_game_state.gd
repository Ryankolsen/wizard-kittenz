extends GutTest

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_game_state_autoload_is_registered():
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload must be registered in project.godot")

func test_current_character_starts_null():
	var gs := get_node("/root/GameState")
	assert_null(gs.current_character)

func test_set_character_persists_data():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Shadow")
	gs.set_character(c)
	assert_eq(gs.current_character, c)
	assert_eq(gs.current_character.character_class, CharacterData.CharacterClass.NINJA)

func test_clear_resets_to_null():
	var gs := get_node("/root/GameState")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.MAGE))
	gs.clear()
	assert_null(gs.current_character)

# --- apply_merged_save --------------------------------------------------------

func test_apply_merged_save_hydrates_character():
	var gs := get_node("/root/GameState")
	var save := KittenSaveData.new()
	save.character_name = "Mittens"
	save.character_class = CharacterData.CharacterClass.THIEF
	save.level = 5
	save.xp = 42
	gs.apply_merged_save(save)
	assert_not_null(gs.current_character, "current_character set")
	assert_eq(gs.current_character.character_name, "Mittens", "name")
	assert_eq(gs.current_character.level, 5, "level")
	assert_eq(gs.current_character.xp, 42, "xp")

func test_apply_merged_save_updates_meta_tracker():
	var gs := get_node("/root/GameState")
	var save := KittenSaveData.new()
	save.dungeons_completed = 9
	gs.apply_merged_save(save)
	assert_eq(gs.meta_tracker.dungeons_completed, 9)

func test_game_state_has_no_token_inventory_property():
	# Token economy removed in #30. GameState must not expose a
	# token_inventory field; the property is gone, not just nulled.
	var gs := get_node("/root/GameState")
	assert_false("token_inventory" in gs,
		"token_inventory property must be absent after token economy removal")

func test_apply_merged_save_updates_offline_xp_tracker():
	var gs := get_node("/root/GameState")
	var save := KittenSaveData.new()
	save.offline_xp_earned = 200
	gs.apply_merged_save(save)
	assert_eq(gs.offline_xp_tracker.pending_xp, 200)
