extends GutTest

const TMP_PATH := "user://test_save.json"

func after_each():
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

func test_add_xp_increments_current_xp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var levels := ProgressionSystem.add_xp(c, 3)
	assert_eq(c.xp, 3, "xp accumulates")
	assert_eq(c.level, 1, "no level-up under threshold")
	assert_eq(levels, 0, "no levels gained")

func test_add_xp_with_zero_or_negative_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	assert_eq(ProgressionSystem.add_xp(c, 0), 0)
	assert_eq(c.xp, 0)
	assert_eq(ProgressionSystem.add_xp(c, -10), 0, "negative xp is rejected, not subtracted")
	assert_eq(c.xp, 0)

func test_xp_to_next_level_curve():
	assert_eq(ProgressionSystem.xp_to_next_level(1), 5, "L1->L2 needs 5 xp")
	assert_eq(ProgressionSystem.xp_to_next_level(2), 10, "L2->L3 needs 10 xp")
	assert_eq(ProgressionSystem.xp_to_next_level(3), 15)

func test_level_up_at_exact_threshold_resets_xp_to_zero():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var levels := ProgressionSystem.add_xp(c, 5)
	assert_eq(c.level, 2, "level advances from 1 to 2")
	assert_eq(c.xp, 0, "xp resets to remainder (0 here)")
	assert_eq(levels, 1)

func test_level_up_carries_xp_remainder_into_next_level():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	# Adding 7 xp at L1 (threshold 5) should level up and leave 2 xp toward L3.
	ProgressionSystem.add_xp(c, 7)
	assert_eq(c.level, 2)
	assert_eq(c.xp, 2, "remainder carries forward")

func test_stat_scaling_increases_max_hp_on_level_up():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var hp_before := c.max_hp
	assert_eq(hp_before, 8, "mage starts at 8 max_hp")
	ProgressionSystem.add_xp(c, 5)
	assert_eq(c.level, 2)
	assert_eq(c.max_hp, 10, "+2 max_hp on level-up matches base_max_hp_for curve")
	assert_gt(c.max_hp, hp_before, "stat strictly increases with level")

func test_level_up_heals_by_max_hp_delta_without_overhealing():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	c.take_damage(5)
	var hp_before := c.hp
	ProgressionSystem.add_xp(c, 5)
	assert_eq(c.level, 2)
	# +2 max_hp, hp should rise by 2 but not exceed new max.
	assert_eq(c.hp, hp_before + 2, "level-up heals by max_hp delta")
	assert_lte(c.hp, c.max_hp, "hp never exceeds max_hp")

func test_no_level_overflow_with_huge_xp_dump():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	# Total xp to reach L4 from L1: 5 + 10 + 15 = 30. Add 33 -> end at L4 with 3 xp.
	var levels := ProgressionSystem.add_xp(c, 33)
	assert_eq(levels, 3, "advanced exactly 3 levels")
	assert_eq(c.level, 4)
	assert_eq(c.xp, 3, "remainder is non-negative and correct")
	assert_gte(c.xp, 0, "xp never goes negative")

func test_kitten_save_data_round_trips_via_dict():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Shadow")
	c.level = 3
	c.xp = 7
	c.take_damage(2)
	var save_data := KittenSaveData.from_character(c)
	var dict := save_data.to_dict()
	var restored := KittenSaveData.from_dict(dict)
	assert_eq(restored.character_name, "Shadow")
	assert_eq(restored.character_class, int(CharacterData.CharacterClass.NINJA))
	assert_eq(restored.level, 3)
	assert_eq(restored.xp, 7)
	assert_eq(restored.hp, c.hp)
	assert_eq(restored.max_hp, c.max_hp)
	assert_eq(restored.attack, c.attack)
	assert_eq(restored.defense, c.defense)

func test_save_manager_round_trip_preserves_level_and_xp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.THIEF, "Whiskers")
	ProgressionSystem.add_xp(c, 17)  # L1->L2 (5) + L2->L3 (10) leaves 2 xp at L3
	assert_eq(c.level, 3)
	assert_eq(c.xp, 2)

	var err := SaveManager.save(c, TMP_PATH)
	assert_eq(err, OK)

	var loaded := SaveManager.load(TMP_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.character_name, "Whiskers")
	assert_eq(loaded.character_class, int(CharacterData.CharacterClass.THIEF))
	assert_eq(loaded.level, 3, "saved level survives round-trip")
	assert_eq(loaded.xp, 2, "saved xp survives round-trip")
	assert_eq(loaded.max_hp, c.max_hp)
	assert_eq(loaded.hp, c.hp)

func test_save_manager_load_missing_returns_null():
	assert_null(SaveManager.load("user://does_not_exist.json"))

func test_save_manager_apply_to_restores_character_data():
	var original := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "Shadow")
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
	var player := CharacterData.make_new(CharacterData.CharacterClass.NINJA)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var reward := enemy.xp_reward
	while enemy.is_alive():
		DamageResolver.apply(player, enemy)
	assert_false(enemy.is_alive())
	ProgressionSystem.add_xp(player, reward)
	assert_eq(player.xp, reward, "killed enemy's xp_reward lands on the player")
