extends GutTest

const TMP_PATH := "user://test_character.tres"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

# Regression (#337): the CharacterClass enum starts at 6, so indexing
# keys() by the enum value (keys()[character_class]) reads the wrong name
# for every class and runs off the end for SLEEPY_KITTEN (8) and up,
# crashing co-op join/create. class_name_for maps value -> name correctly.
func test_class_name_for_maps_every_class_value_to_its_enum_name():
	for name in CharacterData.CharacterClass.keys():
		var value: int = CharacterData.CharacterClass[name]
		assert_eq(CharacterData.class_name_for(value), name,
			"class_name_for(%d) must return %s" % [value, name])

func test_make_new_mage_has_expected_defaults():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Whiskers")
	assert_eq(c.character_name, "Whiskers")
	assert_eq(c.character_class, CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(c.level, 1)
	assert_eq(c.xp, 0)
	assert_eq(c.max_hp, 6, "wizard starts with 6 max hp (PRD #316)")
	assert_eq(c.hp, c.max_hp, "new character starts at full hp")

func test_make_new_battle_and_sleepy_have_class_specific_hp():
	var battle := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var sleepy := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_eq(battle.max_hp, 10)
	assert_eq(sleepy.max_hp, 9)

func test_make_new_sets_class_specific_attack_and_defense():
	var wizard := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var battle := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var sleepy := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_eq(wizard.attack, 1)
	assert_eq(wizard.defense, 0)
	assert_eq(battle.attack, 7, "battle has the highest base attack")
	assert_eq(battle.defense, 1, "battle carries a defense baseline")
	assert_eq(sleepy.attack, 2)
	assert_eq(sleepy.defense, 0)

func test_max_hp_scales_with_level():
	assert_eq(CharacterData.base_max_hp_for(CharacterData.CharacterClass.WIZARD_KITTEN, 1), 6)
	assert_eq(CharacterData.base_max_hp_for(CharacterData.CharacterClass.WIZARD_KITTEN, 2), 8)
	assert_eq(CharacterData.base_max_hp_for(CharacterData.CharacterClass.WIZARD_KITTEN, 5), 14)

func test_take_damage_reduces_hp_and_clamps_at_zero():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(c.take_damage(3), 3)
	assert_eq(c.hp, 7)
	assert_true(c.is_alive())
	assert_eq(c.take_damage(99), 7, "overkill returns only damage actually dealt")
	assert_eq(c.hp, 0)
	assert_false(c.is_alive())

func test_heal_increases_hp_and_clamps_at_max():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.take_damage(8)
	assert_eq(c.hp, 2)
	assert_eq(c.heal(3), 3)
	assert_eq(c.hp, 5)
	assert_eq(c.heal(99), 5, "overheal returns only healing actually applied")
	assert_eq(c.hp, c.max_hp)

func test_save_and_load_roundtrips_state():
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN, "Shadow")
	c.xp = 42
	c.take_damage(3)
	var err := c.save_to(TMP_PATH)
	assert_eq(err, OK, "save should succeed")

	var loaded := CharacterData.load_from(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.character_name, "Shadow")
	assert_eq(loaded.character_class, CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_eq(loaded.xp, 42)
	assert_eq(loaded.hp, c.hp)
	assert_eq(loaded.max_hp, c.max_hp)

func test_load_from_missing_path_returns_null():
	assert_null(CharacterData.load_from("user://does_not_exist.tres"))

func test_expanded_stat_set_fields_exist():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_true("magic_attack" in c)
	assert_true("magic_points" in c)
	assert_true("max_mp" in c)
	assert_true("magic_resistance" in c)
	assert_true("dexterity" in c)
	assert_true("evasion" in c)
	assert_true("crit_chance" in c)
	assert_true("luck" in c)
	assert_true("regeneration" in c)

func test_expanded_stat_set_field_types():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(typeof(c.evasion), TYPE_FLOAT)
	assert_eq(typeof(c.crit_chance), TYPE_FLOAT)
	assert_eq(typeof(c.magic_attack), TYPE_INT)
	assert_eq(typeof(c.magic_points), TYPE_INT)
	assert_eq(typeof(c.max_mp), TYPE_INT)
	assert_eq(typeof(c.magic_resistance), TYPE_INT)
	assert_eq(typeof(c.dexterity), TYPE_INT)
	assert_eq(typeof(c.luck), TYPE_INT)
	assert_eq(typeof(c.regeneration), TYPE_INT)

func test_make_new_sets_class_specific_magic_defaults():
	var mage := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var thief := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_gt(mage.magic_attack, 0, "mage starts with non-zero magic_attack")
	assert_gt(mage.max_mp, 0, "mage starts with non-zero max_mp")
	assert_eq(mage.magic_points, mage.max_mp, "new mage starts at full mp")
	assert_gt(mage.magic_attack, thief.magic_attack, "mage out-magics thief")
	assert_gt(mage.max_mp, thief.max_mp, "mage has more mp than thief")

func test_save_load_roundtrips_expanded_stat_set():
	var tmp := "user://test_kitten_save_expanded.json"
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.magic_attack = 7
	c.magic_points = 4
	c.max_mp = 5
	c.magic_resistance = 2
	c.dexterity = 6
	c.evasion = 0.15
	c.crit_chance = 0.10
	c.luck = 3
	c.regeneration = 1
	var err := SaveManager.save(c, tmp)
	assert_eq(err, OK)
	var loaded := SaveManager.load(tmp)
	assert_not_null(loaded)
	var restored := CharacterData.new()
	loaded.apply_to(restored)
	assert_eq(restored.magic_attack, 7)
	assert_eq(restored.magic_points, 4)
	assert_eq(restored.max_mp, 5)
	assert_eq(restored.magic_resistance, 2)
	assert_eq(restored.dexterity, 6)
	assert_almost_eq(restored.evasion, 0.15, 0.001)
	assert_almost_eq(restored.crit_chance, 0.10, 0.001)
	assert_eq(restored.luck, 3)
	assert_eq(restored.regeneration, 1)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

func test_apply_stat_delta_increases_int_stat():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var before := c.attack
	c.apply_stat_delta("attack", 3.0)
	assert_eq(c.attack, before + 3)

func test_apply_stat_delta_decreases_int_stat():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var before := c.attack
	c.apply_stat_delta("attack", -1.0)
	assert_eq(c.attack, before - 1)

func test_apply_stat_delta_rounds_float_delta_for_int_stat():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var before := c.attack
	c.apply_stat_delta("attack", 1.7)
	assert_eq(c.attack, before + 2, "rounds to nearest, not truncates")

func test_apply_stat_delta_float_stat_stays_float():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.apply_stat_delta("evasion", 0.15)
	assert_almost_eq(c.evasion, 0.15, 0.001)
	assert_eq(typeof(c.evasion), TYPE_FLOAT)

func test_apply_stat_delta_empty_name_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var before := c.attack
	c.apply_stat_delta("", 5.0)
	assert_eq(c.attack, before)

func test_apply_stat_delta_unknown_name_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.apply_stat_delta("nonexistent_stat", 5.0)
	assert_true(true, "should not crash on unknown stat")

func test_apply_stat_delta_swap_replaces_bonus():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var base_attack := c.attack
	c.apply_stat_delta("attack", 3.0)
	assert_eq(c.attack, base_attack + 3, "old item applied")
	c.apply_stat_delta("attack", -3.0)
	c.apply_stat_delta("attack", 5.0)
	assert_eq(c.attack, base_attack + 5, "swap removes old bonus and applies new")

func test_kitten_class_make_new_sets_class():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(c.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)

func test_kitten_class_stat_archetype_ordering():
	var battle := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var wizard := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var sleepy := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	var chonk := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	# max_hp: chonk > battle >= sleepy > wizard
	assert_gt(chonk.max_hp, battle.max_hp, "chonk tankiest")
	assert_true(battle.max_hp >= sleepy.max_hp, "battle >= sleepy hp")
	assert_gt(sleepy.max_hp, wizard.max_hp, "sleepy > wizard hp")
	# attack: battle highest
	assert_gt(battle.attack, wizard.attack)
	assert_gt(battle.attack, sleepy.attack)
	# magic_attack: wizard > battle
	assert_gt(wizard.magic_attack, battle.magic_attack)
	# defense: chonk > battle
	assert_gt(chonk.defense, battle.defense)
	# speed: chonk < battle
	assert_lt(chonk.speed, battle.speed)
	# max_mp: both casters carry a deep pool; PRD #316 ranks wizard > sleepy.
	assert_gt(wizard.max_mp, sleepy.max_mp)
	assert_gt(sleepy.max_mp, battle.max_mp)
	# regeneration: sleepy highest
	assert_gt(sleepy.regeneration, chonk.regeneration)
	assert_gt(sleepy.regeneration, battle.regeneration)
	assert_gt(sleepy.regeneration, wizard.regeneration)

func test_cat_tier_amplifies_kitten_base():
	var battle_k := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var battle_c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_CAT)
	assert_true(battle_c.attack >= battle_k.attack, "battle cat attack >= kitten")
	var wizard_k := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var wizard_c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_CAT)
	assert_true(wizard_c.magic_attack >= wizard_k.magic_attack, "wizard cat magic >= kitten")
	var sleepy_k := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	var sleepy_c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_CAT)
	assert_true(sleepy_c.regeneration >= sleepy_k.regeneration, "sleepy cat regen >= kitten")
	var chonk_k := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	var chonk_c := CharacterData.make_new(CharacterData.CharacterClass.CHONK_CAT)
	assert_true(chonk_c.max_hp >= chonk_k.max_hp, "chonk cat hp >= kitten")

func test_make_new_sleepy_has_positive_regeneration():
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_gt(c.regeneration, 0)

# --- Regen gating (issue #142) --------------------------------------------

func test_sleepy_kitten_starts_at_two_regen():
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_eq(c.regeneration, 2, "Sleepy Kitten baseline regen is 2 (PRD #316)")

func test_non_sleepy_class_starts_at_zero_regen():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(c.regeneration, 0, "Non-Sleepy classes have regen locked at 0")

func test_sleepy_kitten_regen_investment_capped_at_five():
	# PRD #316: Sleepy regen is Primary with explicit +5 cap.
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.skill_points = 10
	for _i in range(10):
		StatAllocator.allocate(c, {"regeneration": 1})
	var max_after_invest: int = 2 + ClassStatTiers.SLEEPY_REGEN_CAP
	assert_true(c.regeneration <= max_after_invest,
		"Sleepy regen capped at baseline 2 + invest cap 5, got %d" % c.regeneration)

func test_non_sleepy_class_cannot_invest_regen():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 1
	var ok := StatAllocator.allocate(c, {"regeneration": 1})
	assert_false(ok, "non-Sleepy classes cannot invest stat points in regen")
	assert_eq(c.regeneration, 0, "regen unchanged after rejected investment")
	assert_eq(c.skill_points, 1, "skill_points unchanged after rejected investment")

func test_item_regen_applies_in_full_for_non_sleepy_class():
	# PRD #316: items bypass class tier caps so loot drops always feel useful.
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var item := ItemData.new()
	item.slot = ItemData.Slot.ACCESSORY
	item.bonuses = [StatBonus.make("regeneration", 2.0)] as Array[StatBonus]
	var inv := ItemInventory.new()
	inv.equip(item)
	ItemStatApplicator.apply(inv, c)
	assert_eq(c.regeneration, 2, "items apply regen bonus regardless of tier")

func test_make_new_mage_classes_have_mp_regen_baseline():
	var wizard := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(wizard.mp_regen, 1.0, "Wizard Kitten starts with mp_regen = 1.0")
	var sleepy := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_eq(sleepy.mp_regen, 1.5, "Sleepy Kitten starts with mp_regen = 1.5 (PRD #316)")

func test_make_new_physical_classes_have_zero_mp_regen():
	var battle := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(battle.mp_regen, 0.0, "Battle Kitten starts with mp_regen = 0.0")
	var chonk := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	assert_eq(chonk.mp_regen, 0.0, "Chonk Kitten starts with mp_regen = 0.0")

func test_mp_regen_survives_clone():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.mp_regen = 2.5
	var copy := c.clone()
	assert_eq(copy.mp_regen, 2.5, "mp_regen preserved through clone()")

func test_stat_allocator_can_invest_in_mp_regen():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 2
	var before := c.mp_regen
	var ok := StatAllocator.allocate(c, {"mp_regen": 2})
	assert_true(ok, "mp_regen allocation succeeds")
	assert_eq(c.mp_regen, before + 2.0, "each skill point adds 1.0 mp_regen")
	assert_eq(c.skill_points, 0, "skill points consumed")

func test_save_load_roundtrips_chonk_kitten():
	var c := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN, "Biscuit")
	var err := c.save_to(TMP_PATH)
	assert_eq(err, OK)
	var loaded := CharacterData.load_from(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.character_class, CharacterData.CharacterClass.CHONK_KITTEN)
	assert_eq(loaded.max_hp, c.max_hp)

func test_pre_prd_save_loads_with_zero_defaults():
	var old_dict := {
		"character_name": "Kitten",
		"character_class": int(CharacterData.CharacterClass.BATTLE_KITTEN),
		"level": 3,
		"xp": 0,
		"hp": 10,
		"max_hp": 10,
		"attack": 2,
		"defense": 0,
		"speed": 60.0,
		"skill_points": 0,
	}
	var save_data := KittenSaveData.from_dict(old_dict)
	var c := CharacterData.new()
	save_data.apply_to(c)
	assert_eq(c.magic_attack, 0)
	assert_eq(c.magic_points, 0)
	assert_eq(c.max_mp, 0)
	assert_eq(c.magic_resistance, 0)
	assert_eq(c.dexterity, 0)
	assert_almost_eq(c.evasion, 0.0, 0.001)
	assert_almost_eq(c.crit_chance, 0.0, 0.001)
	assert_eq(c.luck, 0)
	assert_eq(c.regeneration, 0)

# --- PRD #316 / issue #318: widened base stats per class (Kitten tier) ------

func test_wizard_kitten_base_stats_match_prd():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(c.max_hp, 6)
	assert_eq(c.max_mp, 14)
	assert_eq(c.attack, 1)
	assert_eq(c.magic_attack, 8)
	assert_eq(c.defense, 0)
	assert_eq(c.magic_resistance, 1)
	assert_almost_eq(c.speed, 60.0, 0.001)
	assert_almost_eq(c.mp_regen, 1.0, 0.001)
	assert_eq(c.regeneration, 0)

func test_battle_kitten_base_stats_match_prd():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(c.max_hp, 10)
	assert_eq(c.max_mp, 4)
	assert_eq(c.attack, 7)
	assert_eq(c.magic_attack, 0)
	assert_eq(c.defense, 1)
	assert_eq(c.magic_resistance, 0)
	assert_almost_eq(c.speed, 70.0, 0.001)
	assert_almost_eq(c.mp_regen, 0.0, 0.001)
	assert_eq(c.regeneration, 0)

func test_sleepy_kitten_base_stats_match_prd():
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_eq(c.max_hp, 9)
	assert_eq(c.max_mp, 12)
	assert_eq(c.attack, 2)
	assert_eq(c.magic_attack, 4)
	assert_eq(c.defense, 0)
	assert_eq(c.magic_resistance, 1)
	assert_almost_eq(c.speed, 52.0, 0.001)
	assert_almost_eq(c.mp_regen, 1.5, 0.001)
	assert_eq(c.regeneration, 2)

func test_chonk_kitten_base_stats_match_prd():
	var c := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	assert_eq(c.max_hp, 18)
	assert_eq(c.max_mp, 2)
	assert_eq(c.attack, 4)
	assert_eq(c.magic_attack, 0)
	assert_eq(c.defense, 5)
	assert_eq(c.magic_resistance, 2)
	assert_almost_eq(c.speed, 52.0, 0.001)
	assert_almost_eq(c.mp_regen, 0.0, 0.001)
	assert_eq(c.regeneration, 0)

func test_hp_level_scaling_unchanged():
	# +2 per level over Wizard's new 6 baseline -> 10 at level 3.
	assert_eq(CharacterData.base_max_hp_for(
		CharacterData.CharacterClass.WIZARD_KITTEN, 3), 10)

func test_chonk_and_sleepy_share_speed_baseline():
	# PRD #316 acceptance criterion: Chonk and Sleepy both sit at 52.
	var chonk := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	var sleepy := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	assert_almost_eq(chonk.speed, 52.0, 0.001)
	assert_almost_eq(sleepy.speed, 52.0, 0.001)
