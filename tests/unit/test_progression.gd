extends GutTest

const TMP_PATH := "user://test_save.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func test_add_xp_increments_current_xp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var levels := ProgressionSystem.add_xp(c, 3)
	assert_eq(c.xp, 3, "xp accumulates")
	assert_eq(c.level, 1, "no level-up under threshold")
	assert_eq(levels, 0, "no levels gained")

func test_add_xp_with_zero_or_negative_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_eq(ProgressionSystem.add_xp(c, 0), 0)
	assert_eq(c.xp, 0)
	assert_eq(ProgressionSystem.add_xp(c, -10), 0, "negative xp is rejected, not subtracted")
	assert_eq(c.xp, 0)

func test_xp_to_next_level_curve():
	# Soft power curve floor(100 * n^1.5).
	assert_eq(ProgressionSystem.xp_to_next_level(1), 100, "L1->L2 needs 100 xp")
	assert_eq(ProgressionSystem.xp_to_next_level(2), 282, "L2->L3: floor(100 * 2^1.5) = 282")
	assert_eq(ProgressionSystem.xp_to_next_level(3), 519, "L3->L4: floor(100 * 3^1.5) = 519")

func test_xp_to_next_level_curve_at_milestones():
	# Pin the curve at the round-decade levels the PRD calls out.
	assert_eq(ProgressionSystem.xp_to_next_level(10), 3162,
		"L10->L11: floor(100 * 10^1.5)")
	assert_eq(ProgressionSystem.xp_to_next_level(20), 8944,
		"L20->L21: floor(100 * 20^1.5)")

func test_xp_base_constant_gates_entire_curve():
	# The XP_BASE constant is the single tuning knob; doubling it doubles
	# every threshold.
	assert_eq(ProgressionSystem.XP_BASE, 100, "default XP_BASE is 100")
	# Re-derive thresholds from XP_BASE rather than hardcoding so the test
	# stays honest if the constant moves.
	assert_eq(ProgressionSystem.xp_to_next_level(1), ProgressionSystem.XP_BASE)

func test_stat_points_per_level_scales_every_ten_levels():
	# Levels 1-10 award 3 points each, 11-20 award 4, 21-30 award 5.
	assert_eq(ProgressionSystem.stat_points_for_level(2), 3, "L2 award is 3")
	assert_eq(ProgressionSystem.stat_points_for_level(10), 3, "L10 award is 3")
	assert_eq(ProgressionSystem.stat_points_for_level(11), 4, "L11 award is 4")
	assert_eq(ProgressionSystem.stat_points_for_level(20), 4, "L20 award is 4")
	assert_eq(ProgressionSystem.stat_points_for_level(21), 5, "L21 award is 5")
	assert_eq(ProgressionSystem.stat_points_for_level(30), 5, "L30 award is 5")

func test_level_up_awards_three_points_in_first_tier():
	# Level 1 -> 2 grants 3 stat points (3 + floor((2-1)/10) = 3).
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1))
	assert_eq(c.level, 2)
	assert_eq(c.skill_points, 3)

func test_level_up_awards_four_points_in_second_tier():
	# Level 10 -> 11 grants 4 stat points.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.level = 10
	c.xp = 0
	c.skill_points = 0
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(10))
	assert_eq(c.level, 11)
	assert_eq(c.skill_points, 4)

func test_level_up_awards_five_points_in_third_tier():
	# Level 20 -> 21 grants 5 stat points.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.level = 20
	c.xp = 0
	c.skill_points = 0
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(20))
	assert_eq(c.level, 21)
	assert_eq(c.skill_points, 5)

func test_level_up_at_exact_threshold_resets_xp_to_zero():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var levels := ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1))
	assert_eq(c.level, 2, "level advances from 1 to 2")
	assert_eq(c.xp, 0, "xp resets to remainder (0 here)")
	assert_eq(levels, 1)

func test_level_up_carries_xp_remainder_into_next_level():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	# Adding (threshold + 2) xp at L1 should level up and leave 2 xp toward L3.
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1) + 2)
	assert_eq(c.level, 2)
	assert_eq(c.xp, 2, "remainder carries forward")

func test_stat_scaling_increases_max_hp_on_level_up():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var hp_before := c.max_hp
	assert_eq(hp_before, 8, "mage starts at 8 max_hp")
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1))
	assert_eq(c.level, 2)
	assert_eq(c.max_hp, 10, "+2 max_hp on level-up matches base_max_hp_for curve")
	assert_gt(c.max_hp, hp_before, "stat strictly increases with level")

func test_level_up_heals_by_max_hp_delta_without_overhealing():
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.take_damage(5)
	var hp_before := c.hp
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1))
	assert_eq(c.level, 2)
	# +2 max_hp, hp should rise by 2 but not exceed new max.
	assert_eq(c.hp, hp_before + 2, "level-up heals by max_hp delta")
	assert_lte(c.hp, c.max_hp, "hp never exceeds max_hp")

func test_no_level_overflow_with_huge_xp_dump():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	# Sum of thresholds 1..3 = 100 + 282 + 519 = 901. Add 904 -> L4 with 3 xp.
	var total: int = ProgressionSystem.xp_to_next_level(1) \
		+ ProgressionSystem.xp_to_next_level(2) \
		+ ProgressionSystem.xp_to_next_level(3) \
		+ 3
	var levels := ProgressionSystem.add_xp(c, total)
	assert_eq(levels, 3, "advanced exactly 3 levels")
	assert_eq(c.level, 4)
	assert_eq(c.xp, 3, "remainder is non-negative and correct")
	assert_gte(c.xp, 0, "xp never goes negative")

func test_kitten_save_data_round_trips_via_dict():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Shadow")
	c.level = 3
	c.xp = 7
	c.take_damage(2)
	var save_data := KittenSaveData.from_character(c)
	var dict := save_data.to_dict()
	var restored := KittenSaveData.from_dict(dict)
	assert_eq(restored.character_name, "Shadow")
	assert_eq(restored.character_class, int(CharacterData.CharacterClass.BATTLE_KITTEN))
	assert_eq(restored.level, 3)
	assert_eq(restored.xp, 7)
	assert_eq(restored.hp, c.hp)
	assert_eq(restored.max_hp, c.max_hp)
	assert_eq(restored.attack, c.attack)
	assert_eq(restored.defense, c.defense)

func test_save_manager_round_trip_preserves_level_and_xp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Whiskers")
	# L1->L2 (100) + L2->L3 (282) leaves 2 xp at L3 after adding 384.
	var total: int = ProgressionSystem.xp_to_next_level(1) \
		+ ProgressionSystem.xp_to_next_level(2) + 2
	ProgressionSystem.add_xp(c, total)
	assert_eq(c.level, 3)
	assert_eq(c.xp, 2)

	var err := SaveManager.save(c, TMP_PATH)
	assert_eq(err, OK)

	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.character_name, "Whiskers")
	assert_eq(loaded.character_class, int(CharacterData.CharacterClass.BATTLE_KITTEN))
	assert_eq(loaded.level, 3, "saved level survives round-trip")
	assert_eq(loaded.xp, 2, "saved xp survives round-trip")
	assert_eq(loaded.max_hp, c.max_hp)
	assert_eq(loaded.hp, c.hp)

func test_save_manager_load_missing_returns_null():
	assert_null(SaveManager.load("user://does_not_exist.json"))

func test_save_manager_apply_to_restores_character_data():
	var original := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN, "Shadow")
	ProgressionSystem.add_xp(original, 12)
	SaveManager.save(original, TMP_PATH)

	var loaded := SaveManager.load(TMP_PATH)
	var restored := CharacterData.new()
	loaded.apply_to(restored)
	assert_eq(restored.character_name, original.character_name)
	assert_eq(restored.character_class, original.character_class)
	assert_eq(restored.level, original.level)
	assert_eq(restored.xp, original.xp)
	assert_eq(restored.max_hp, original.max_hp)

func test_killing_enemy_awards_xp_via_progression_system():
	# Simulates the player.gd flow: damage until dead, then award xp_reward.
	var player := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var reward := enemy.xp_reward
	while enemy.is_alive():
		DamageResolver.apply(player, enemy)
	assert_false(enemy.is_alive())
	ProgressionSystem.add_xp(player, reward)
	assert_eq(player.xp, reward, "killed enemy's xp_reward lands on the player")
