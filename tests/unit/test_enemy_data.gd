extends GutTest

func test_make_new_slime_has_expected_defaults():
	var e := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	assert_eq(e.kind, EnemyData.EnemyKind.SLIME)
	assert_eq(e.enemy_name, "Slime")
	assert_eq(e.max_hp, 4)
	assert_eq(e.hp, 4)
	assert_eq(e.attack, 1)
	assert_eq(e.defense, 0)
	assert_eq(e.xp_reward, 2)

func test_make_new_each_kind_has_distinct_stats():
	var slime := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var bat := EnemyData.make_new(EnemyData.EnemyKind.BAT)
	var rat := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	assert_eq(bat.max_hp, 3)
	assert_eq(bat.attack, 1)
	assert_eq(rat.max_hp, 5)
	assert_eq(rat.attack, 2)
	assert_eq(rat.defense, 1, "rat is the only kind with defense baseline")
	assert_eq(rat.xp_reward, 3)
	assert_ne(slime.enemy_name, rat.enemy_name)

func test_take_damage_clamps_and_kills():
	var e := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	assert_true(e.is_alive())
	assert_eq(e.take_damage(2), 2)
	assert_eq(e.hp, 3)
	assert_eq(e.take_damage(99), 3, "overkill returns only damage actually dealt")
	assert_eq(e.hp, 0)
	assert_false(e.is_alive())

func test_make_new_returns_independent_instances():
	var a := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var b := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	a.take_damage(99)
	assert_eq(a.hp, 0)
	assert_eq(b.hp, 4, "second instance should be untouched")

func test_static_helpers_match_make_new():
	for k in [EnemyData.EnemyKind.SLIME, EnemyData.EnemyKind.BAT, EnemyData.EnemyKind.RAT]:
		var e := EnemyData.make_new(k)
		assert_eq(e.max_hp, EnemyData.base_max_hp_for(k))
		assert_eq(e.attack, EnemyData.base_attack_for(k))
		assert_eq(e.defense, EnemyData.base_defense_for(k))
		assert_eq(e.xp_reward, EnemyData.base_xp_for(k))
		assert_eq(e.enemy_name, EnemyData.display_name_for(k))
