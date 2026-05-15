extends GutTest

# --- Issue tests ---

func test_factory_battle_has_higher_speed_than_chonk():
	# Core wiring — CharacterFactory.create_default("battle_kitten")
	# returns a kitten with higher base speed than create_default("chonk_kitten").
	var battle: CharacterData = CharacterFactory.create_default("battle_kitten")
	var chonk: CharacterData = CharacterFactory.create_default("chonk_kitten")
	assert_gt(battle.speed, chonk.speed, "battle outpaces chonk from the start")

func test_battle_base_attack_higher_than_wizard():
	# Battle Kitten base attack > Wizard Kitten base attack.
	var battle: CharacterData = CharacterFactory.create_default("battle_kitten")
	var wizard: CharacterData = CharacterFactory.create_default("wizard_kitten")
	assert_gt(battle.attack, wizard.attack, "battle hits harder than wizard at level 1")

func test_thief_and_ninja_skill_trees_are_independent():
	# Issue test 3: unlocking a Thief skill node does not mutate the Ninja
	# skill tree. Each make_*_tree() factory builds fresh nodes; this guards
	# against regressions where someone accidentally shares a node array.
	var thief_tree := SkillTree.make_thief_tree()
	var ninja_tree := SkillTree.make_ninja_tree()
	var thief: CharacterData = CharacterFactory.create_default("Thief")
	thief.skill_points = 1
	var thief_mgr := SkillTreeManager.make(thief_tree, thief)

	assert_true(thief_mgr.unlock("backstab"), "thief unlocks backstab")
	assert_true(thief_tree.find("backstab").unlocked)

	# Ninja tree must be untouched. shuriken_throw is the ninja base node and
	# starts locked.
	assert_false(ninja_tree.find("shuriken_throw").unlocked, "ninja tree is untouched")
	# And no node accidentally shared the "backstab" id across trees.
	assert_null(ninja_tree.find("backstab"), "thief node id does not exist on ninja tree")

func test_backstab_deals_more_damage_from_behind():
	# Issue test 4: ThiefAbilities.backstab(attacker, target) deals more
	# damage when attacking from behind (target facing away) than from front.
	# Same direction = attacker is behind; opposite directions = face-to-face.
	var attacker_front: CharacterData = CharacterFactory.create_default("Thief")
	var target_front: EnemyData = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	# Make the slime tankier so the front swing doesn't land at the floor of 1.
	target_front.max_hp = 50
	target_front.hp = 50
	attacker_front.facing = Vector2.RIGHT
	target_front.facing = Vector2.LEFT  # facing the attacker -> front
	var front_damage := ThiefAbilities.backstab(attacker_front, target_front)

	var attacker_behind: CharacterData = CharacterFactory.create_default("Thief")
	var target_behind: EnemyData = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	target_behind.max_hp = 50
	target_behind.hp = 50
	attacker_behind.facing = Vector2.RIGHT
	target_behind.facing = Vector2.RIGHT  # walking away -> attacker is behind
	var behind_damage := ThiefAbilities.backstab(attacker_behind, target_behind)

	assert_gt(behind_damage, front_damage, "backstab from behind hits harder than from front")

# --- Coverage extras ---

func test_factory_create_default_is_case_insensitive():
	# The picker UI passes whatever-case name the user clicks; resolve robustly.
	var t1: CharacterData = CharacterFactory.create_default("battle_kitten")
	var t2: CharacterData = CharacterFactory.create_default("THIEF")
	assert_eq(t1.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(t2.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)

func test_factory_unknown_name_falls_back_to_battle_kitten():
	var c: CharacterData = CharacterFactory.create_default("paladin")
	assert_eq(c.character_class, CharacterData.CharacterClass.BATTLE_KITTEN,
		"unknown class name lands on the default Kitten starter")

func test_factory_carries_custom_name():
	var c: CharacterData = CharacterFactory.create_default("sleepy_kitten", "Whiskers")
	assert_eq(c.character_name, "Whiskers")
	assert_eq(c.character_class, CharacterData.CharacterClass.SLEEPY_KITTEN)

func test_thief_tree_progression_is_chained():
	# Can't unlock smoke_bomb without backstab, can't unlock shadow_step
	# without smoke_bomb. Same prereq shape as the mage tree.
	var tree := SkillTree.make_thief_tree()
	var c: CharacterData = CharacterFactory.create_default("Thief")
	c.skill_points = 3
	var mgr := SkillTreeManager.make(tree, c)
	assert_false(mgr.can_unlock("smoke_bomb"), "smoke_bomb gated on backstab")
	assert_false(mgr.can_unlock("shadow_step"), "shadow_step gated on smoke_bomb")
	assert_true(mgr.unlock("backstab"))
	assert_true(mgr.unlock("smoke_bomb"))
	assert_true(mgr.unlock("shadow_step"))
	assert_eq(c.skill_points, 0, "all three points consumed")

func test_ninja_tree_progression_is_chained():
	var tree := SkillTree.make_ninja_tree()
	var c: CharacterData = CharacterFactory.create_default("Ninja")
	c.skill_points = 3
	var mgr := SkillTreeManager.make(tree, c)
	assert_true(mgr.unlock("shuriken_throw"))
	assert_true(mgr.unlock("blade_storm"))
	assert_true(mgr.unlock("vanish"))

func test_ninja_tree_has_distinct_effect_kinds():
	# Acceptance criterion mirror of the mage tree: each spell carries a
	# distinct EffectKind so the resolver dispatches to a unique branch.
	var tree := SkillTree.make_ninja_tree()
	assert_eq(tree.find("shuriken_throw").spell.effect_kind, Spell.EffectKind.DAMAGE)
	assert_eq(tree.find("blade_storm").spell.effect_kind, Spell.EffectKind.AREA)
	assert_eq(tree.find("vanish").spell.effect_kind, Spell.EffectKind.BUFF)

func test_thief_tree_has_distinct_effect_kinds():
	var tree := SkillTree.make_thief_tree()
	assert_eq(tree.find("backstab").spell.effect_kind, Spell.EffectKind.DAMAGE)
	assert_eq(tree.find("smoke_bomb").spell.effect_kind, Spell.EffectKind.AREA)
	assert_eq(tree.find("shadow_step").spell.effect_kind, Spell.EffectKind.BUFF)

func test_classes_have_visually_distinct_base_stats():
	# Acceptance criterion: each class is distinguishable on the picker.
	# Burn at least one stat into a difference for every pair.
	var wizard: CharacterData = CharacterFactory.create_default("wizard_kitten")
	var battle: CharacterData = CharacterFactory.create_default("battle_kitten")
	var chonk: CharacterData = CharacterFactory.create_default("chonk_kitten")
	# Battle vs Wizard: attack and hp.
	assert_ne(battle.attack, wizard.attack)
	assert_ne(battle.max_hp, wizard.max_hp)
	# Chonk vs Wizard: defense and speed.
	assert_ne(chonk.defense, wizard.defense)
	# Battle vs Chonk: speed (chonk slower than battle).
	assert_ne(battle.speed, chonk.speed)

func test_backstab_zero_attack_deals_no_damage_even_from_behind():
	# Preserves DamageResolver's invariant: a 0-attack swing is harmless
	# regardless of facing. Otherwise a turned-away target would eat free
	# damage from a stat-zeroed debuffed attacker.
	var attacker := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	attacker.attack = 0
	attacker.facing = Vector2.UP
	var target := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	target.facing = Vector2.UP
	var hp_before := target.hp
	assert_eq(ThiefAbilities.backstab(attacker, target), 0)
	assert_eq(target.hp, hp_before, "no hp change on zero-attack backstab")

func test_backstab_floor_one_damage_when_defense_exceeds_attack():
	var attacker := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	attacker.attack = 2
	attacker.facing = Vector2.UP
	var target := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	target.defense = 99
	target.facing = Vector2.LEFT  # facing toward attacker -> front
	# Front: floor at 1. Behind: 1 * 2 = 2.
	var dealt := ThiefAbilities.backstab(attacker, target)
	assert_eq(dealt, 1, "front-stab floors at 1 even vs heavy defense")

func test_backstab_zero_facing_treated_as_not_behind():
	# Defensive: a freshly-spawned target with facing == Vector2.ZERO would
	# trip a divide-by-zero on normalize. Treat it as "front" so the bonus
	# never accidentally fires on uninitialized state.
	var attacker := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	attacker.facing = Vector2.RIGHT
	var target := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	target.facing = Vector2.ZERO
	assert_false(ThiefAbilities.is_behind(attacker, target))

func test_game_state_builds_correct_tree_per_class():
	# _build_tree_for picks the right factory for each class. Failure mode is
	# silent (wrong tree returned) so an explicit guard is worth it.
	# Updated for #127: each Kitten archetype has its own factory.
	var battle := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	GameState.set_character(battle)
	assert_not_null(GameState.skill_tree.find("paw_smash"), "battle kitten gets battle tree")
	assert_null(GameState.skill_tree.find("hairball_hex"), "battle tree has no wizard nodes")

	var chonk := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN)
	GameState.set_character(chonk)
	assert_not_null(GameState.skill_tree.find("chonk_taunt"), "chonk kitten gets chonk tree")
	assert_null(GameState.skill_tree.find("paw_smash"), "chonk tree has no battle nodes")

	var wizard := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	GameState.set_character(wizard)
	assert_not_null(GameState.skill_tree.find("hairball_hex"))

	GameState.clear()

func test_save_layer_round_trips_speed():
	# speed is a per-class derived stat but still flows through the JSON
	# blob — guards the picker -> save -> restart -> load loop.
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var save_data := KittenSaveData.from_character(c)
	var restored := KittenSaveData.from_dict(save_data.to_dict())
	assert_eq(restored.speed, c.speed)

# --- Kitten class factory wiring (#119) ---

func test_factory_creates_wizard_kitten():
	var c: CharacterData = CharacterFactory.create_default("wizard_kitten")
	assert_eq(c.character_class, CharacterData.CharacterClass.WIZARD_KITTEN)

func test_factory_creates_battle_kitten():
	var c: CharacterData = CharacterFactory.create_default("battle_kitten")
	assert_eq(c.character_class, CharacterData.CharacterClass.BATTLE_KITTEN)

func test_factory_creates_chonk_kitten():
	var c: CharacterData = CharacterFactory.create_default("chonk_kitten")
	assert_eq(c.character_class, CharacterData.CharacterClass.CHONK_KITTEN)

func test_factory_all_eight_kitten_keys_round_trip():
	# Each new class id round-trips through class_from_name / name_from_class.
	var pairs := {
		"battle_kitten": CharacterData.CharacterClass.BATTLE_KITTEN,
		"wizard_kitten": CharacterData.CharacterClass.WIZARD_KITTEN,
		"sleepy_kitten": CharacterData.CharacterClass.SLEEPY_KITTEN,
		"chonk_kitten": CharacterData.CharacterClass.CHONK_KITTEN,
		"battle_cat": CharacterData.CharacterClass.BATTLE_CAT,
		"wizard_cat": CharacterData.CharacterClass.WIZARD_CAT,
		"sleepy_cat": CharacterData.CharacterClass.SLEEPY_CAT,
		"chonk_cat": CharacterData.CharacterClass.CHONK_CAT,
	}
	for key in pairs:
		var expected: int = pairs[key]
		assert_eq(CharacterFactory.class_from_name(key), expected,
			"class_from_name(%s) -> %d" % [key, expected])
		assert_eq(CharacterFactory.name_from_class(expected), key,
			"name_from_class(%d) -> %s" % [expected, key])

func test_factory_chonk_kitten_case_insensitive():
	# UI bindings may surface uppercase; resolve robustly.
	var c: CharacterData = CharacterFactory.create_default("CHONK_KITTEN")
	assert_eq(c.character_class, CharacterData.CharacterClass.CHONK_KITTEN)
