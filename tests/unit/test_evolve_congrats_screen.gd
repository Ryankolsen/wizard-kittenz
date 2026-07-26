extends GutTest

# PRD #439 / issue #441 — EvolveCongratsScreen is a CanvasLayer overlay shown
# after a Shop class-tier upgrade. This slice is the static populate() +
# dismiss wiring; the animated sprite/flash sequence is #442.

const SCENE_PATH := "res://scenes/evolve_congrats_screen.tscn"

func _instantiate() -> EvolveCongratsScreen:
	var scene: EvolveCongratsScreen = load(SCENE_PATH).instantiate()
	add_child_autofree(scene)
	return scene

func test_scene_has_required_nodes():
	var s := _instantiate()
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/Headline"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/TierName"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/SpriteRow/OldSprite"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/SpriteRow/NewSprite"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/StatDeltaList"))
	assert_not_null(s.get_node_or_null("Backdrop/Center/Panel/VBox/ContinueButton"))

func test_populate_sets_headline_and_tier_name():
	var s := _instantiate()
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	var headline: Label = s.get_node("Backdrop/Center/Panel/VBox/Headline")
	var tier_name: Label = s.get_node("Backdrop/Center/Panel/VBox/TierName")
	assert_true(headline.text.length() > 0)
	assert_eq(tier_name.text, "Battle Cat")

func test_populate_sets_sprite_textures():
	var s := _instantiate()
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	var old_sprite: TextureRect = s.get_node("Backdrop/Center/Panel/VBox/SpriteRow/OldSprite")
	var new_sprite: TextureRect = s.get_node("Backdrop/Center/Panel/VBox/SpriteRow/NewSprite")
	assert_not_null(old_sprite.texture)
	assert_not_null(new_sprite.texture)
	assert_ne(old_sprite.texture, new_sprite.texture)

func test_populate_renders_one_row_per_stat_delta():
	var s := _instantiate()
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	var list: VBoxContainer = s.get_node("Backdrop/Center/Panel/VBox/StatDeltaList")
	assert_eq(list.get_child_count(), 4)
	var found_attack_row := false
	for child in list.get_children():
		if child.text.find("Attack") != -1 and child.text.find("+2") != -1:
			found_attack_row = true
	assert_true(found_attack_row, "expected a stat-delta row containing 'Attack' and '+2'")

func test_populate_before_ready_is_safe():
	var s := EvolveCongratsScreen.new()
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	add_child_autofree(s)
	await get_tree().process_frame
	var headline: Label = s.get_node("Backdrop/Center/Panel/VBox/Headline")
	assert_true(headline.text.length() > 0)

func test_continue_pressed_emits_dismissed():
	var s := _instantiate()
	watch_signals(s)
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ContinueButton")
	btn.pressed.emit()
	assert_signal_emitted(s, "dismissed")

func test_continue_pressed_does_not_free_screen():
	var s := _instantiate()
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ContinueButton")
	btn.pressed.emit()
	assert_true(is_instance_valid(s))

# --- #442 tween-based transformation + flash sequence ----------------------

func test_populate_starts_transformation_sequence():
	var s := _instantiate()
	watch_signals(s)
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	await s.transformation_finished
	assert_signal_emitted(s, "transformation_finished")

func test_initial_state_after_populate_before_animation():
	var s := _instantiate()
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	var old_sprite: TextureRect = s.get_node("Backdrop/Center/Panel/VBox/SpriteRow/OldSprite")
	var new_sprite: TextureRect = s.get_node("Backdrop/Center/Panel/VBox/SpriteRow/NewSprite")
	assert_eq(old_sprite.modulate.a, 1.0)
	assert_eq(new_sprite.modulate.a, 0.0)

func test_final_state_after_transformation_finished():
	var s := _instantiate()
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	await s.transformation_finished
	var new_sprite: TextureRect = s.get_node("Backdrop/Center/Panel/VBox/SpriteRow/NewSprite")
	var flash_overlay: ColorRect = s.get_node("FlashOverlay")
	assert_eq(new_sprite.modulate.a, 1.0)
	assert_eq(flash_overlay.color.a, 0.0)

func test_continue_button_disabled_until_transformation_finished():
	var s := _instantiate()
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	var btn: Button = s.get_node("Backdrop/Center/Panel/VBox/ContinueButton")
	assert_true(btn.disabled)
	await s.transformation_finished
	assert_false(btn.disabled)

func test_calling_populate_twice_does_not_stack_tweens():
	var s := _instantiate()
	watch_signals(s)
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	s.populate(CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT,
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0})
	await s.transformation_finished
	assert_signal_emit_count(s, "transformation_finished", 1)
