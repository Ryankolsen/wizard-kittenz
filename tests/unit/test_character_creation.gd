extends GutTest

# Existing select_class tests (kept — guards the legacy compat shim still
# used by callers that take a CharacterClass enum directly).
func test_select_class_mage_makes_mage_with_default_name():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(c.character_class, CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(c.character_name, "Kitten")
	assert_eq(c.max_hp, 8, "mage default max_hp comes from CharacterData baseline")
	assert_eq(c.hp, c.max_hp, "new character starts at full hp")

func test_select_class_thief_uses_thief_baseline():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(c.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(c.max_hp, 10)

func test_select_class_sleepy_uses_sleepy_baseline_and_custom_name():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.SLEEPY_KITTEN, "Shadow")
	assert_eq(c.character_class, CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_eq(c.character_name, "Shadow")
	assert_eq(c.max_hp, 10)

func test_select_class_returns_independent_instances():
	var a := CharacterCreation.select_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	var b := CharacterCreation.select_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_ne(a.get_instance_id(), b.get_instance_id(), "each pick should return a fresh CharacterData")
	a.take_damage(3)
	assert_eq(b.hp, b.max_hp, "mutating one pick must not affect another")

# Issue acceptance: Quick Start path returns a CharacterData with the
# named class set and a non-empty (silly-pool) name.
func test_quick_start_returns_thief_with_non_empty_name():
	var c := QuickStartController.create_for_class("Thief")
	assert_eq(c.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_true(c.character_name.length() > 0, "quick start picks a non-empty silly name")

func test_quick_start_returns_mage_with_non_empty_name():
	var c := QuickStartController.create_for_class("wizard_kitten")
	assert_eq(c.character_class, CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_true(c.character_name.length() > 0)

func test_quick_start_unknown_class_falls_through_to_battle_kitten():
	# CharacterFactory.class_from_name maps unknown -> BATTLE_KITTEN; QuickStart
	# inherits that contract so a typo from a UI binding won't crash.
	var c := QuickStartController.create_for_class("totally-not-a-class")
	assert_eq(c.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_true(c.character_name.length() > 0)

func test_quick_start_handles_archmage_string():
	var c := QuickStartController.create_for_class("wizard_cat")
	assert_eq(c.character_class, CharacterData.CharacterClass.WIZARD_CAT)

# Issue acceptance: NameSuggester surfaces silly names without consecutive
# duplicates across 10 calls.
func test_name_suggester_returns_non_empty_strings():
	var s := NameSuggester.new()
	for i in range(10):
		assert_true(s.get_random_name().length() > 0)

func test_name_suggester_no_consecutive_duplicates_in_ten_calls():
	var s := NameSuggester.new()
	var prev := s.get_random_name()
	for i in range(10):
		var pick := s.get_random_name()
		assert_ne(pick, prev, "consecutive draws must differ")
		prev = pick

func test_name_suggester_pool_has_at_least_ten_silly_names():
	# The "silly suggested name pool surfaces at least 10 names" criterion.
	# Read off the constant directly so the test fails loudly if a future
	# edit shrinks the pool below the contract.
	assert_true(NameSuggester.SILLY_NAMES.size() >= 10,
		"silly name pool must contain >= 10 entries")

func test_name_suggester_pool_includes_signature_silly_names():
	# Sanity-check that the canonical exemplars from the issue are present.
	# Locks the *content* of the pool, not just its size — protects against
	# a refactor that swaps the pool for a generic boring name list.
	assert_true("Bourbon Cat" in NameSuggester.SILLY_NAMES)
	assert_true("Catnip McGee" in NameSuggester.SILLY_NAMES)

func test_name_suggester_seeded_is_deterministic():
	# Same seed -> same sequence; covers test-friendly determinism.
	var a := NameSuggester.new(42)
	var b := NameSuggester.new(42)
	for i in range(5):
		assert_eq(a.get_random_name(), b.get_random_name())

func test_name_suggester_different_seeds_diverge():
	# Cheap heuristic that two different seeds produce different sequences;
	# guards against a future bug where the rng isn't actually seeded.
	var a := NameSuggester.new(1)
	var b := NameSuggester.new(2)
	var diverged := false
	for i in range(5):
		if a.get_random_name() != b.get_random_name():
			diverged = true
			break
	assert_true(diverged, "different seeds must produce different sequences in 5 draws")

# Issue acceptance: editing identity (name + appearance) must not reset
# xp / level / skill_points. Locks the "Edit Kitten from pause menu does
# not reset progression" criterion at the data layer; the future pause
# menu UI calls apply_identity_edit directly.
func test_apply_identity_edit_preserves_progression():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Old")
	c.xp = 42
	c.level = 5
	c.skill_points = 3
	c.appearance_index = 0
	QuickStartController.apply_identity_edit(c, "New", 4)
	assert_eq(c.character_name, "New")
	assert_eq(c.appearance_index, 4)
	assert_eq(c.xp, 42, "edit must not reset xp")
	assert_eq(c.level, 5, "edit must not reset level")
	assert_eq(c.skill_points, 3, "edit must not reset skill points")

func test_apply_identity_edit_blank_name_is_ignored():
	# Empty / whitespace name keeps the previous one — prevents the user
	# from accidentally erasing their kitten's name with the Save button.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Whiskers")
	QuickStartController.apply_identity_edit(c, "   ", 2)
	assert_eq(c.character_name, "Whiskers")
	assert_eq(c.appearance_index, 2, "appearance still updates even when name is blank")

func test_apply_identity_edit_handles_null_safely():
	# No-op on null — defensive; the future pause-menu wiring may briefly
	# pass null while the GameState.current_character autoload is hydrating.
	QuickStartController.apply_identity_edit(null, "X", 1)
	assert_true(true, "null path must not crash")

# CharacterData appearance_index round-trips through the save layer so
# the chosen sprite-sheet index survives a session restart (load contract).
func test_appearance_index_round_trips_via_save_data():
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN, "Pixel")
	c.appearance_index = 5
	var save := KittenSaveData.from_character(c)
	var dict := save.to_dict()
	var restored := KittenSaveData.from_dict(dict)
	assert_eq(restored.appearance_index, 5)

func test_legacy_save_without_appearance_index_defaults_to_zero():
	# Saves predating this field must load as appearance_index=0 rather
	# than crash. Mirrors the same migration contract used for other
	# JSON-shaped projection fields.
	var legacy := {
		"character_name": "Old",
		"character_class": int(CharacterData.CharacterClass.WIZARD_KITTEN),
		"level": 1,
		"xp": 0,
	}
	var s := KittenSaveData.from_dict(legacy)
	assert_eq(s.appearance_index, 0)

func test_apply_to_writes_appearance_index_back_to_character():
	# Round-trip the other direction: a loaded save must hydrate the
	# appearance_index onto the live CharacterData so the renderer can
	# read it without re-parsing the dict.
	var s := KittenSaveData.new()
	s.appearance_index = 3
	var c := CharacterData.new()
	s.apply_to(c)
	assert_eq(c.appearance_index, 3)

# --- Issue #122: four-class Kitten picker ---

const _SUBTITLES := {
	"BattleKittenButton": "Melee Damage",
	"WizardKittenButton": "Attack Mage",
	"SleepyKittenButton": "Healer",
	"ChonkKittenButton": "Tank",
}

const _BUTTON_TO_CLASS := {
	"BattleKittenButton": CharacterData.CharacterClass.BATTLE_KITTEN,
	"WizardKittenButton": CharacterData.CharacterClass.WIZARD_KITTEN,
	"SleepyKittenButton": CharacterData.CharacterClass.SLEEPY_KITTEN,
	"ChonkKittenButton": CharacterData.CharacterClass.CHONK_KITTEN,
}

func _instantiate_creation_scene() -> Node:
	# Pre-clear current_character so _ready's save-exists probe doesn't
	# leak state between tests (and so the QuickStart panel isn't gated
	# behind the overwrite-confirm dialog mid-test).
	GameState.current_character = null
	GameState.meta_tracker = MetaProgressionTracker.new()
	GameState.unlock_registry = UnlockRegistry.make_default()
	var scene = load("res://scenes/character_creation.tscn").instantiate()
	add_child_autofree(scene)
	return scene

func test_quick_start_panel_has_four_kitten_buttons():
	var scene := _instantiate_creation_scene()
	for btn_name in _BUTTON_TO_CLASS.keys():
		var btn := scene.find_child(btn_name, true, false) as Button
		assert_not_null(btn, "QuickStart must contain %s" % btn_name)

func _btn_path(panel: String, btn_name: String) -> String:
	# Each kitten button lives inside a sibling <Class>Group VBoxContainer
	# (so the Subtitle Label can stack under it). Strip the trailing
	# "Button" to derive the group name.
	var group := btn_name.replace("Button", "Group")
	return "%s/VBox/Buttons/%s/%s" % [panel, group, btn_name]

func test_customize_panel_has_four_kitten_buttons():
	var scene := _instantiate_creation_scene()
	# find_child returns the first match; verify both panels contain the
	# button by counting via get_node on the explicit path.
	for btn_name in _BUTTON_TO_CLASS.keys():
		var btn := scene.get_node(_btn_path("Customize", btn_name)) as Button
		assert_not_null(btn, "Customize must contain %s" % btn_name)

func test_each_quick_start_button_has_correct_subtitle():
	var scene := _instantiate_creation_scene()
	for btn_name in _SUBTITLES.keys():
		var group_path := _btn_path("QuickStart", btn_name).get_base_dir()
		var group := scene.get_node(group_path)
		var subtitle := group.find_child("Subtitle", false, false) as Label
		assert_not_null(subtitle, "%s should have a sibling Subtitle Label" % btn_name)
		assert_eq(subtitle.text, _SUBTITLES[btn_name])

func test_each_customize_button_has_correct_subtitle():
	var scene := _instantiate_creation_scene()
	for btn_name in _SUBTITLES.keys():
		var group_path := _btn_path("Customize", btn_name).get_base_dir()
		var group := scene.get_node(group_path)
		var subtitle := group.find_child("Subtitle", false, false) as Label
		assert_not_null(subtitle, "%s should have a sibling Subtitle Label" % btn_name)
		assert_eq(subtitle.text, _SUBTITLES[btn_name])

func test_quick_start_battle_kitten_button_creates_battle_kitten():
	# Core wiring AC: pressing Battle Kitten in QuickStart yields a
	# CharacterData with character_class == BATTLE_KITTEN. We intercept
	# at GameState.current_character so the press doesn't have to actually
	# change scenes.
	var scene := _instantiate_creation_scene()
	var btn := scene.get_node(_btn_path("QuickStart", "BattleKittenButton")) as Button
	btn.pressed.emit()
	assert_not_null(GameState.current_character)
	assert_eq(GameState.current_character.character_class,
		CharacterData.CharacterClass.BATTLE_KITTEN)

func test_all_four_quick_start_buttons_select_correct_class():
	for btn_name in _BUTTON_TO_CLASS.keys():
		var scene := _instantiate_creation_scene()
		var btn := scene.get_node(_btn_path("QuickStart", btn_name)) as Button
		btn.pressed.emit()
		assert_eq(GameState.current_character.character_class,
			_BUTTON_TO_CLASS[btn_name],
			"QuickStart %s must select %s" % [btn_name, _BUTTON_TO_CLASS[btn_name]])

func test_all_four_customize_buttons_select_correct_class():
	for btn_name in _BUTTON_TO_CLASS.keys():
		var scene := _instantiate_creation_scene()
		var btn := scene.get_node(_btn_path("Customize", btn_name)) as Button
		btn.pressed.emit()
		assert_eq(GameState.current_character.character_class,
			_BUTTON_TO_CLASS[btn_name],
			"Customize %s must select %s" % [btn_name, _BUTTON_TO_CLASS[btn_name]])

func test_chonk_kitten_disabled_at_zero_dungeons():
	var scene := _instantiate_creation_scene()
	var qs_chonk := scene.get_node(_btn_path("QuickStart", "ChonkKittenButton")) as Button
	var custom_chonk := scene.get_node(_btn_path("Customize", "ChonkKittenButton")) as Button
	assert_true(qs_chonk.disabled, "Chonk Kitten gated until threshold met")
	assert_true(custom_chonk.disabled, "Chonk Kitten gated until threshold met")

func test_chonk_kitten_enabled_after_threshold():
	GameState.current_character = null
	GameState.meta_tracker = MetaProgressionTracker.new()
	GameState.meta_tracker.dungeons_completed = 5
	GameState.unlock_registry = UnlockRegistry.make_default()
	var scene = load("res://scenes/character_creation.tscn").instantiate()
	add_child_autofree(scene)
	var qs_chonk := scene.get_node(_btn_path("QuickStart", "ChonkKittenButton")) as Button
	var custom_chonk := scene.get_node(_btn_path("Customize", "ChonkKittenButton")) as Button
	assert_false(qs_chonk.disabled, "Chonk Kitten unlocked once threshold met")
	assert_false(custom_chonk.disabled, "Chonk Kitten unlocked once threshold met")

func test_multiplayer_fallback_defaults_to_battle_kitten():
	var scene = _instantiate_creation_scene()
	var data = scene._ensure_character_for_multiplayer()
	assert_eq(data.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(GameState.current_character.character_class,
		CharacterData.CharacterClass.BATTLE_KITTEN)

func test_no_legacy_class_buttons_remain():
	var scene := _instantiate_creation_scene()
	for legacy in ["MageButton", "ThiefButton", "NinjaButton"]:
		assert_null(scene.find_child(legacy, true, false),
			"Legacy %s must be removed from the picker" % legacy)
