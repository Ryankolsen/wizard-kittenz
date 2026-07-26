extends GutTest

# Issue #127: four class-specific skill tree factories.

const BATTLE_NODES := [
	["paw_smash", 1, Spell.EffectKind.DAMAGE],
	["hissy_fit", 3, Spell.EffectKind.DAMAGE],
	["fur_missile", 5, Spell.EffectKind.DAMAGE],
	["cat_nap", 8, Spell.EffectKind.AREA],
	["feral_frenzy", 12, Spell.EffectKind.AREA],
]
const WIZARD_NODES := [
	["hairball_hex", 1, Spell.EffectKind.DAMAGE],
	["catnip_curse", 3, Spell.EffectKind.BUFF],
	["whisker_bolt", 5, Spell.EffectKind.DAMAGE],
	["litter_storm", 8, Spell.EffectKind.AREA],
	["arcane_purr", 12, Spell.EffectKind.DAMAGE],
]
const SLEEPY_NODES := [
	["fuzzy_warmth", 1, Spell.EffectKind.SMART_HEAL],
	["cozy_aura", 3, Spell.EffectKind.PARTY_BUFF],
	["warm_blanket", 5, Spell.EffectKind.AOE_HEAL],
	["regen_snooze", 8, Spell.EffectKind.GROUP_REGEN],
	["nap_of_the_gods", 12, Spell.EffectKind.AOE_HEAL],
]
const CHONK_NODES := [
	["chonk_taunt", 1, Spell.EffectKind.TAUNT],
	["belly_flop", 3, Spell.EffectKind.AREA],
	["sit_on_it", 5, Spell.EffectKind.DAMAGE],
	["hairball_horrors", 8, Spell.EffectKind.AREA],
	["maximum_chonk", 12, Spell.EffectKind.BUFF],
]

func test_battle_kitten_tree_has_5_nodes():
	var t := SkillTree.make_battle_kitten_tree()
	assert_eq(t.nodes.size(), 5)

func test_wizard_kitten_tree_has_5_nodes():
	assert_eq(SkillTree.make_wizard_kitten_tree().nodes.size(), 5)

func test_sleepy_kitten_tree_has_5_nodes():
	assert_eq(SkillTree.make_sleepy_kitten_tree().nodes.size(), 5)

func test_chonk_kitten_tree_has_5_nodes():
	assert_eq(SkillTree.make_chonk_kitten_tree().nodes.size(), 5)

func _assert_roster(tree: SkillTree, roster: Array, label: String) -> void:
	for entry in roster:
		var node_id: String = entry[0]
		var lvl: int = entry[1]
		var kind: int = entry[2]
		var n := tree.find(node_id)
		assert_not_null(n, "%s: node %s should exist" % [label, node_id])
		if n == null:
			continue
		assert_eq(n.level_required, lvl, "%s: %s level_required" % [label, node_id])
		assert_not_null(n.spell, "%s: %s spell" % [label, node_id])
		assert_eq(n.spell.effect_kind, kind, "%s: %s effect_kind" % [label, node_id])
		assert_true(n.prerequisite_ids.is_empty(), "%s: %s has no prerequisites" % [label, node_id])

func test_battle_kitten_roster():
	_assert_roster(SkillTree.make_battle_kitten_tree(), BATTLE_NODES, "Battle")

func test_wizard_kitten_roster():
	_assert_roster(SkillTree.make_wizard_kitten_tree(), WIZARD_NODES, "Wizard")

func test_sleepy_kitten_roster():
	_assert_roster(SkillTree.make_sleepy_kitten_tree(), SLEEPY_NODES, "Sleepy")

func test_sleepy_kitten_dream_bubble_removed():
	assert_null(SkillTree.make_sleepy_kitten_tree().find("dream_bubble"))

func test_sleepy_kitten_regen_snooze_exists():
	assert_not_null(SkillTree.make_sleepy_kitten_tree().find("regen_snooze"))

func test_chonk_kitten_roster():
	_assert_roster(SkillTree.make_chonk_kitten_tree(), CHONK_NODES, "Chonk")

func test_no_prerequisites_anywhere():
	var trees := [
		SkillTree.make_battle_kitten_tree(),
		SkillTree.make_wizard_kitten_tree(),
		SkillTree.make_sleepy_kitten_tree(),
		SkillTree.make_chonk_kitten_tree(),
	]
	for tree in trees:
		for node in tree.nodes:
			assert_true(node.prerequisite_ids.is_empty(), "no prereqs for %s" % node.id)

func test_game_state_routes_battle_kitten():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN))
	assert_not_null(gs.skill_tree.find("paw_smash"))

func test_game_state_routes_wizard_kitten():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN))
	assert_not_null(gs.skill_tree.find("hairball_hex"))

func test_game_state_routes_sleepy_kitten():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN))
	assert_not_null(gs.skill_tree.find("fuzzy_warmth"))

func test_game_state_routes_chonk_kitten():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN))
	assert_not_null(gs.skill_tree.find("chonk_taunt"))

func test_battle_cat_shares_kitten_tree():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.BATTLE_CAT))
	assert_not_null(gs.skill_tree.find("paw_smash"))

func test_wizard_cat_shares_kitten_tree():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.WIZARD_CAT))
	assert_not_null(gs.skill_tree.find("hairball_hex"))

func test_sleepy_cat_shares_kitten_tree():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_CAT))
	assert_not_null(gs.skill_tree.find("fuzzy_warmth"))

func test_chonk_cat_shares_kitten_tree():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.CHONK_CAT))
	assert_not_null(gs.skill_tree.find("chonk_taunt"))

# ---- Cat-tier walking skeleton: Claw Storm (PRD #418 / issue #420) -------

func test_battle_cat_tree_includes_claw_storm():
	var t := SkillTree.make_battle_cat_tree()
	var n := t.find("claw_storm")
	assert_not_null(n, "Battle Cat tree should contain Claw Storm")
	if n == null:
		return
	assert_eq(n.level_required, 15)
	assert_eq(n.spell.effect_kind, Spell.EffectKind.DAMAGE)
	assert_eq(n.spell.power, 16)
	assert_almost_eq(n.spell.cooldown, 1.5, 0.001)
	assert_eq(n.prerequisite_ids, ["feral_frenzy"],
		"Claw Storm requires the Battle Kitten capstone as a prerequisite")

func test_battle_kitten_tree_does_not_include_claw_storm():
	assert_null(SkillTree.make_battle_kitten_tree().find("claw_storm"),
		"Claw Storm is a Cat-tier-only node")

func test_game_state_routes_battle_kitten_without_claw_storm():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN))
	assert_null(gs.skill_tree.find("claw_storm"),
		"Battle Kitten tree does not contain the Cat-tier node")

func test_game_state_routes_battle_cat_with_claw_storm():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.BATTLE_CAT))
	assert_not_null(gs.skill_tree.find("claw_storm"),
		"Battle Cat tree contains the Cat-tier node")

func test_level_30_battle_kitten_does_not_unlock_claw_storm():
	# Acceptance criterion: a level-30 character still in Kitten form does
	# NOT have Claw Storm unlocked (it isn't even in the Kitten's tree).
	var gs = _fresh_game_state()
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	c.level = 30
	gs.set_character(c)
	assert_null(gs.skill_tree.find("claw_storm"))

func test_level_15_battle_cat_unlocks_claw_storm():
	# Acceptance criterion: a level-15 Battle Cat DOES have Claw Storm unlocked.
	var gs = _fresh_game_state()
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_CAT)
	c.level = 15
	gs.set_character(c)
	assert_true(gs.skill_tree.is_unlocked("claw_storm"))

func _fresh_game_state():
	return get_node("/root/GameState")

func _build_cat_tree(factory: String) -> SkillTree:
	match factory:
		"make_battle_cat_tree":
			return SkillTree.make_battle_cat_tree()
		"make_wizard_cat_tree":
			return SkillTree.make_wizard_cat_tree()
		"make_sleepy_cat_tree":
			return SkillTree.make_sleepy_cat_tree()
		"make_chonk_cat_tree":
			return SkillTree.make_chonk_cat_tree()
	return null

# ---- Cat-tier roster rollout: remaining 9 nodes (PRD #418 / issue #422) --

# [tree_factory, node_id, level, effect_kind, power, cooldown, mp_cost, prereq_id]
const CAT_ROSTER := [
	["make_battle_cat_tree", "pounce", 18, Spell.EffectKind.DAMAGE, 14, 2.0, 0, "claw_storm"],
	["make_battle_cat_tree", "apex_predator", 30, Spell.EffectKind.AREA, 26, 7.0, 0, "pounce"],
	["make_wizard_cat_tree", "supernova_swat", 22, Spell.EffectKind.DAMAGE, 22, 5.0, 14, "arcane_purr"],
	["make_wizard_cat_tree", "starfall", 26, Spell.EffectKind.AREA, 18, 6.0, 16, "supernova_swat"],
	["make_wizard_cat_tree", "archmagus_ascension", 30, Spell.EffectKind.DAMAGE, 30, 8.0, 20, "starfall"],
	["make_sleepy_cat_tree", "cozy_cocoon", 15, Spell.EffectKind.PARTY_SHIELD, 10, 5.0, 10, "nap_of_the_gods"],
	["make_sleepy_cat_tree", "purrfect_remedy", 18, Spell.EffectKind.AOE_HEAL, 18, 4.0, 12, "cozy_cocoon"],
	["make_sleepy_cat_tree", "dream_sanctuary", 26, Spell.EffectKind.GROUP_REGEN, 4, 6.0, 14, "purrfect_remedy"],
	["make_sleepy_cat_tree", "nine_lives", 30, Spell.EffectKind.SMART_HEAL, 0, 10.0, 20, "dream_sanctuary"],
	["make_chonk_cat_tree", "gravity_well", 15, Spell.EffectKind.AREA, 16, 4.0, 0, "maximum_chonk"],
	["make_chonk_cat_tree", "iron_hide", 22, Spell.EffectKind.BUFF, 0, 10.0, 0, "gravity_well"],
	["make_chonk_cat_tree", "thunderous_belly_flop", 26, Spell.EffectKind.AREA, 22, 5.0, 0, "iron_hide"],
]

func test_cat_roster_node_wiring():
	for entry in CAT_ROSTER:
		var factory: String = entry[0]
		var node_id: String = entry[1]
		var lvl: int = entry[2]
		var kind: int = entry[3]
		var power: int = entry[4]
		var cd: float = entry[5]
		var mp: int = entry[6]
		var prereq: String = entry[7]
		var t: SkillTree = _build_cat_tree(factory)
		var n := t.find(node_id)
		assert_not_null(n, "%s: node %s should exist" % [factory, node_id])
		if n == null:
			continue
		assert_eq(n.level_required, lvl, "%s level_required" % node_id)
		assert_not_null(n.spell, "%s spell" % node_id)
		assert_eq(n.spell.effect_kind, kind, "%s effect_kind" % node_id)
		assert_eq(n.spell.power, power, "%s power" % node_id)
		assert_almost_eq(n.spell.cooldown, cd, 0.001, "%s cooldown" % node_id)
		assert_eq(n.spell.mp_cost, mp, "%s mp_cost" % node_id)
		assert_eq(n.prerequisite_ids, [prereq], "%s prerequisite" % node_id)

func test_capstones_at_level_30():
	assert_eq(SkillTree.make_battle_cat_tree().find("apex_predator").level_required, 30)
	assert_eq(SkillTree.make_wizard_cat_tree().find("archmagus_ascension").level_required, 30)
	assert_eq(SkillTree.make_sleepy_cat_tree().find("nine_lives").level_required, 30)

func test_cat_roster_gated_to_matching_cat_class():
	for entry in CAT_ROSTER:
		var t: SkillTree = _build_cat_tree(entry[0])
		var n := t.find(entry[1])
		if n == null:
			continue
		assert_ne(n.required_class, -1, "%s must be class-gated" % entry[1])

func test_new_nodes_absent_from_kitten_trees():
	var kitten_trees := {
		"battle": SkillTree.make_battle_kitten_tree(),
		"wizard": SkillTree.make_wizard_kitten_tree(),
		"sleepy": SkillTree.make_sleepy_kitten_tree(),
		"chonk": SkillTree.make_chonk_kitten_tree(),
	}
	for entry in CAT_ROSTER:
		var node_id: String = entry[1]
		for label in kitten_trees:
			assert_null(kitten_trees[label].find(node_id), "%s should not be on the %s Kitten tree" % [node_id, label])

func test_cat_roster_one_level_below_gate_stays_locked():
	for entry in CAT_ROSTER:
		var factory: String = entry[0]
		var node_id: String = entry[1]
		var lvl: int = entry[2]
		var t: SkillTree = _build_cat_tree(factory)
		var required_class: int = t.find(node_id).required_class
		var newly := SkillUnlockChecker.auto_unlock_for_level(t, lvl - 1, required_class)
		assert_false(newly.has(node_id), "%s should stay locked one level below its gate" % node_id)

func test_cat_roster_unlocks_at_gate_for_matching_class():
	for entry in CAT_ROSTER:
		var factory: String = entry[0]
		var node_id: String = entry[1]
		var lvl: int = entry[2]
		var t: SkillTree = _build_cat_tree(factory)
		var required_class: int = t.find(node_id).required_class
		var newly := SkillUnlockChecker.auto_unlock_for_level(t, lvl, required_class)
		assert_true(newly.has(node_id), "%s should unlock at its gate for the matching class" % node_id)

func test_cat_roster_stays_locked_for_kitten_variant_even_above_level():
	# Regression on #420's class-aware gating: the Kitten variant's own tree
	# doesn't even contain these nodes, so a Kitten at/above the gate level
	# never has them — covered structurally by
	# test_new_nodes_absent_from_kitten_trees, plus a direct GameState check.
	var gs = _fresh_game_state()
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.level = 30
	gs.set_character(c)
	assert_null(gs.skill_tree.find("archmagus_ascension"))

func test_game_state_routes_wizard_cat_with_new_nodes():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.WIZARD_CAT))
	assert_not_null(gs.skill_tree.find("supernova_swat"))

func test_game_state_routes_sleepy_cat_with_new_nodes():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_CAT))
	assert_not_null(gs.skill_tree.find("purrfect_remedy"))

func test_game_state_routes_chonk_cat_with_new_nodes():
	var gs = _fresh_game_state()
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.CHONK_CAT))
	assert_not_null(gs.skill_tree.find("gravity_well"))

# Issue #177: mp_cost on mage skill trees.

func test_wizard_kitten_spells_all_have_mp_cost():
	var tree := SkillTree.make_wizard_kitten_tree()
	for node in tree.nodes:
		assert_not_null(node.spell, "Wizard node %s should have a spell" % node.id)
		assert_gt(node.spell.mp_cost, 0, "Wizard spell %s mp_cost > 0" % node.id)

func test_sleepy_kitten_spells_all_have_mp_cost():
	var tree := SkillTree.make_sleepy_kitten_tree()
	for node in tree.nodes:
		assert_not_null(node.spell, "Sleepy node %s should have a spell" % node.id)
		assert_gt(node.spell.mp_cost, 0, "Sleepy spell %s mp_cost > 0" % node.id)

func test_battle_kitten_spells_have_zero_mp_cost():
	var tree := SkillTree.make_battle_kitten_tree()
	for node in tree.nodes:
		assert_eq(node.spell.mp_cost, 0, "Battle spell %s mp_cost == 0" % node.id)

func test_chonk_kitten_spells_have_zero_mp_cost():
	var tree := SkillTree.make_chonk_kitten_tree()
	for node in tree.nodes:
		assert_eq(node.spell.mp_cost, 0, "Chonk spell %s mp_cost == 0" % node.id)

func test_mage_mp_costs_fit_in_starting_mp_pool():
	# Acceptance: player can always cast at least the cheapest spell from a
	# fresh start — every spell's mp_cost must be <= base_max_mp_for(class, 1).
	var wizard_cap := CharacterData.base_max_mp_for(CharacterData.CharacterClass.WIZARD_KITTEN, 1)
	for node in SkillTree.make_wizard_kitten_tree().nodes:
		assert_lte(node.spell.mp_cost, wizard_cap, "Wizard %s mp_cost <= %d" % [node.id, wizard_cap])
	var sleepy_cap := CharacterData.base_max_mp_for(CharacterData.CharacterClass.SLEEPY_KITTEN, 1)
	for node in SkillTree.make_sleepy_kitten_tree().nodes:
		assert_lte(node.spell.mp_cost, sleepy_cap, "Sleepy %s mp_cost <= %d" % [node.id, sleepy_cap])
