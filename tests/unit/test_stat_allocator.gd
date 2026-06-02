extends GutTest

# Battle Kitten chosen for default `attack` allocations because attack is
# Primary for Battle (post #316) — Wizard's Forbidden attack would mask the
# generic cost/overspend semantics these tests are checking.

func test_allocate_attack_succeeds_and_deducts_skill_points():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 5
	var attack_before := c.attack
	var ok := StatAllocator.allocate(c, {"attack": 2})
	assert_true(ok)
	assert_eq(c.attack, attack_before + 2)
	assert_eq(c.skill_points, 3)

func test_hp_allocation_increases_max_hp_and_current_hp():
	# Chonk has max_hp as Primary (cheap, uncapped) per PRD #316.
	var c := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
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
	# Wizard max_mp is Primary (1 SP/pt).
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 2
	var mp_before := c.max_mp
	StatAllocator.allocate(c, {"max_mp": 2})
	assert_eq(c.max_mp, mp_before + 6)

func test_evasion_increments_by_0_01_per_point():
	# Battle: evasion is Secondary (1 SP/pt).
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 3
	var ok := StatAllocator.allocate(c, {"evasion": 1})
	assert_true(ok)
	assert_almost_eq(c.evasion, 0.01, 0.0001)
	assert_eq(c.skill_points, 2)

func test_crit_chance_increments_by_0_01_per_point():
	# Wizard crit_chance is Secondary (1 SP/pt).
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	StatAllocator.allocate(c, {"crit_chance": 3})
	assert_almost_eq(c.crit_chance, 0.03, 0.0001)
	assert_eq(c.skill_points, 2)

func test_overspend_rejected_no_mutation():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 2
	var attack_before := c.attack
	var ok := StatAllocator.allocate(c, {"attack": 3})
	assert_false(ok)
	assert_eq(c.attack, attack_before)
	assert_eq(c.skill_points, 2)

func test_overspend_across_multiple_stats_rejected_no_mutation():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 3
	var attack_before := c.attack
	var defense_before := c.defense
	var ok := StatAllocator.allocate(c, {"attack": 2, "defense": 2})
	assert_false(ok)
	assert_eq(c.attack, attack_before)
	assert_eq(c.defense, defense_before)
	assert_eq(c.skill_points, 3)

func test_multi_point_dump_to_single_stat():
	# Chonk max_hp is Primary, uncapped — safe target for a 5-point dump.
	var c := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	c.skill_points = 10
	var max_hp_before := c.max_hp
	var ok := StatAllocator.allocate(c, {"max_hp": 5})
	assert_true(ok)
	assert_eq(c.max_hp, max_hp_before + 25)
	assert_eq(c.skill_points, 5)

func test_partial_allocation_subset_of_stats_valid():
	# Sleepy: luck Secondary (1 SP), regeneration Primary cap 5 (1 SP).
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.skill_points = 4
	var ok := StatAllocator.allocate(c, {"luck": 2, "regeneration": 2})
	assert_true(ok)
	assert_eq(c.luck, 2)
	assert_eq(c.regeneration, 3, "baseline 1 + 2 invested = 3")
	assert_eq(c.skill_points, 0)

func test_all_int_stats_one_point_each():
	# Sleepy tier breakdown (PRD #316): magic_attack SEC, magic_resistance SEC,
	# luck SEC, regeneration PRI = 4 stats × 1 SP = 4. attack OFF, defense OFF,
	# dexterity OFF, speed OFF = 4 stats × 2 SP = 8. Total 12 SP.
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.skill_points = 12
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
	var regen_before := c.regeneration
	var ok := StatAllocator.allocate(c, plan)
	assert_true(ok)
	assert_eq(c.attack, attack_before + 1)
	assert_eq(c.magic_attack, magic_attack_before + 1)
	assert_eq(c.defense, 1)
	assert_eq(c.magic_resistance, 1)
	assert_eq(c.dexterity, 1)
	assert_eq(c.luck, 1)
	assert_eq(c.regeneration, regen_before + 1)
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
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 5
	var ok := StatAllocator.allocate(c, {"attack": -1})
	assert_false(ok)
	assert_eq(c.skill_points, 5)

func test_zero_points_in_plan_no_op():
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 5
	var attack_before := c.attack
	var ok := StatAllocator.allocate(c, {"attack": 0})
	assert_true(ok)
	assert_eq(c.attack, attack_before)
	assert_eq(c.skill_points, 5)

# --- PRD #316 tier rules ---------------------------------------------------

func test_forbidden_stat_rejected():
	# Wizard attack is Forbidden — no allocation, no SP deduction.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	var attack_before := c.attack
	var ok := StatAllocator.allocate(c, {"attack": 1})
	assert_false(ok)
	assert_eq(c.attack, attack_before)
	assert_eq(c.skill_points, 5)

func test_off_stat_costs_two_sp_per_point():
	# Wizard defense is Off-stat. 1 pt should cost 2 SP.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	var ok := StatAllocator.allocate(c, {"defense": 1})
	assert_true(ok)
	assert_eq(c.skill_points, 3)

func test_primary_costs_one_sp_per_point():
	# Battle attack is Primary. 3 pts = 3 SP.
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 5
	var ok := StatAllocator.allocate(c, {"attack": 3})
	assert_true(ok)
	assert_eq(c.skill_points, 2)

func test_off_stat_cap_enforced():
	# Wizard defense Off-stat capped at +3. Fourth point rejected.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 20
	var first := StatAllocator.allocate(c, {"defense": 3})
	assert_true(first, "first 3 points fit the Off-stat cap")
	var sp_after_first := c.skill_points
	var def_after_first := c.defense
	var second := StatAllocator.allocate(c, {"defense": 1})
	assert_false(second, "fourth point exceeds Off-stat cap")
	assert_eq(c.defense, def_after_first, "defense unchanged on rejection")
	assert_eq(c.skill_points, sp_after_first, "skill_points unchanged on rejection")

func test_secondary_cap_enforced():
	# Battle max_hp Secondary capped at +10. Eleventh point rejected.
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.skill_points = 20
	assert_true(StatAllocator.allocate(c, {"max_hp": 10}), "first 10 fit Secondary cap")
	assert_false(StatAllocator.allocate(c, {"max_hp": 1}), "11th point exceeds Secondary cap")

func test_sleepy_regen_cap_is_five():
	# Sleepy regen Primary but capped at +5. Sixth point rejected.
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.skill_points = 20
	assert_true(StatAllocator.allocate(c, {"regeneration": 5}), "first 5 fit Sleepy regen cap")
	assert_false(StatAllocator.allocate(c, {"regeneration": 1}), "6th point exceeds Sleepy regen cap")

func test_primary_uncapped():
	# Chonk max_hp Primary, uncapped. 15 pts should succeed.
	var c := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	c.skill_points = 50
	var ok := StatAllocator.allocate(c, {"max_hp": 15})
	assert_true(ok)
	assert_eq(c.skill_points, 35)
