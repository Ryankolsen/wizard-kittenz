extends GutTest

# Existing select_class tests (kept — guards the legacy compat shim still
# used by callers that take a CharacterClass enum directly).
func test_select_class_mage_makes_mage_with_default_name():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.MAGE)
	assert_eq(c.character_class, CharacterData.CharacterClass.MAGE)
	assert_eq(c.character_name, "Kitten")
	assert_eq(c.max_hp, 8, "mage default max_hp comes from CharacterData baseline")
	assert_eq(c.hp, c.max_hp, "new character starts at full hp")

func test_select_class_thief_uses_thief_baseline():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.THIEF)
	assert_eq(c.character_class, CharacterData.CharacterClass.THIEF)
	assert_eq(c.max_hp, 10)

func test_select_class_ninja_uses_ninja_baseline_and_custom_name():
	var c := CharacterCreation.select_class(CharacterData.CharacterClass.NINJA, "Shadow")
	assert_eq(c.character_class, CharacterData.CharacterClass.NINJA)
	assert_eq(c.character_name, "Shadow")
	assert_eq(c.max_hp, 9)

func test_select_class_returns_independent_instances():
	var a := CharacterCreation.select_class(CharacterData.CharacterClass.MAGE)
	var b := CharacterCreation.select_class(CharacterData.CharacterClass.MAGE)
	assert_ne(a.get_instance_id(), b.get_instance_id(), "each pick should return a fresh CharacterData")
	a.take_damage(3)
	assert_eq(b.hp, b.max_hp, "mutating one pick must not affect another")

# Issue acceptance: Quick Start path returns a CharacterData with the
# named class set and a non-empty (silly-pool) name.
func test_quick_start_returns_thief_with_non_empty_name():
	var c := QuickStartController.create_for_class("Thief")
	assert_eq(c.character_class, CharacterData.CharacterClass.THIEF)
	assert_true(c.character_name.length() > 0, "quick start picks a non-empty silly name")

func test_quick_start_returns_mage_with_non_empty_name():
	var c := QuickStartController.create_for_class("mage")
	assert_eq(c.character_class, CharacterData.CharacterClass.MAGE)
	assert_true(c.character_name.length() > 0)

func test_quick_start_unknown_class_falls_through_to_battle_kitten():
	# CharacterFactory.class_from_name maps unknown -> BATTLE_KITTEN; QuickStart
	# inherits that contract so a typo from a UI binding won't crash.
	var c := QuickStartController.create_for_class("totally-not-a-class")
	assert_eq(c.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_true(c.character_name.length() > 0)

func test_quick_start_handles_archmage_string():
	var c := QuickStartController.create_for_class("archmage")
	assert_eq(c.character_class, CharacterData.CharacterClass.ARCHMAGE)

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
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Old")
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
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Whiskers")
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
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Pixel")
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
		"character_class": int(CharacterData.CharacterClass.MAGE),
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
