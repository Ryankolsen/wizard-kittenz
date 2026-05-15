extends GutTest

func test_allocate_attack_succeeds_and_deducts_skill_points():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	var attack_before := c.attack
	var ok := StatAllocator.allocate(c, {"attack": 2})
	assert_true(ok)
	assert_eq(c.attack, attack_before + 2)
	assert_eq(c.skill_points, 3)

func test_hp_allocation_increases_max_hp_and_current_hp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 3
	c.hp = c.max_hp - 2  # not full hp; verify delta applied
	var hp_before := c.hp
	var max_hp_before := c.max_hp
	var ok := StatAllocator.allocate(c, {"max_hp": 2})
	assert_true(ok)
	assert_eq(c.max_hp, max_hp_before + 10)
	assert_eq(c.hp, hp_before + 10)
	assert_eq(c.skill_points, 1)

func test_mp_allocation_increments_max_mp_by_three_per_point():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 2
	var mp_before := c.max_mp
	StatAllocator.allocate(c, {"max_mp": 2})
	assert_eq(c.max_mp, mp_before + 6)

func test_evasion_increments_by_0_01_per_point():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 3
	var ok := StatAllocator.allocate(c, {"evasion": 1})
	assert_true(ok)
	assert_almost_eq(c.evasion, 0.01, 0.0001)
	assert_eq(c.skill_points, 2)

func test_crit_chance_increments_by_0_01_per_point():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	StatAllocator.allocate(c, {"crit_chance": 3})
	assert_almost_eq(c.crit_chance, 0.03, 0.0001)
	assert_eq(c.skill_points, 2)

func test_overspend_rejected_no_mutation():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 2
	var attack_before := c.attack
	var ok := StatAllocator.allocate(c, {"attack": 3})
	assert_false(ok)
	assert_eq(c.attack, attack_before)
	assert_eq(c.skill_points, 2)

func test_overspend_across_multiple_stats_rejected_no_mutation():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 3
	var attack_before := c.attack
	var defense_before := c.defense
	var ok := StatAllocator.allocate(c, {"attack": 2, "defense": 2})
	assert_false(ok)
	assert_eq(c.attack, attack_before)
	assert_eq(c.defense, defense_before)
	assert_eq(c.skill_points, 3)

func test_multi_point_dump_to_single_stat():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 10
	var max_hp_before := c.max_hp
	var ok := StatAllocator.allocate(c, {"max_hp": 5})
	assert_true(ok)
	assert_eq(c.max_hp, max_hp_before + 25)
	assert_eq(c.skill_points, 5)

func test_partial_allocation_subset_of_stats_valid():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 4
	var ok := StatAllocator.allocate(c, {"luck": 2, "regeneration": 2})
	assert_true(ok)
	assert_eq(c.luck, 2)
	assert_eq(c.regeneration, 2)
	assert_eq(c.skill_points, 0)

func test_all_int_stats_one_point_each():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 8
	var plan := {
		"attack": 1,
		"magic_attack": 1,
		"defense": 1,
		"magic_resistance": 1,
		"dexterity": 1,
		"luck": 1,
		"regeneration": 1,
		"speed": 1,
	}
	var attack_before := c.attack
	var magic_attack_before := c.magic_attack
	var speed_before := c.speed
	var ok := StatAllocator.allocate(c, plan)
	assert_true(ok)
	assert_eq(c.attack, attack_before + 1)
	assert_eq(c.magic_attack, magic_attack_before + 1)
	assert_eq(c.defense, 1)
	assert_eq(c.magic_resistance, 1)
	assert_eq(c.dexterity, 1)
	assert_eq(c.luck, 1)
	assert_eq(c.regeneration, 1)
	assert_almost_eq(c.speed, speed_before + 1.0, 0.0001)
	assert_eq(c.skill_points, 0)

func test_empty_plan_succeeds_and_does_not_mutate():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	var ok := StatAllocator.allocate(c, {})
	assert_true(ok)
	assert_eq(c.skill_points, 5)

func test_unknown_stat_rejected():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	var ok := StatAllocator.allocate(c, {"not_a_real_stat": 1})
	assert_false(ok)
	assert_eq(c.skill_points, 5)

func test_negative_points_rejected():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	var ok := StatAllocator.allocate(c, {"attack": -1})
	assert_false(ok)
	assert_eq(c.skill_points, 5)

func test_zero_points_in_plan_no_op():
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	var attack_before := c.attack
	var ok := StatAllocator.allocate(c, {"attack": 0})
	assert_true(ok)
	assert_eq(c.attack, attack_before)
	assert_eq(c.skill_points, 5)
