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
