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
	["fuzzy_warmth", 1, Spell.EffectKind.HEAL],
	["warm_blanket", 3, Spell.EffectKind.HEAL],
	["cozy_aura", 5, Spell.EffectKind.BUFF],
	["dream_bubble", 8, Spell.EffectKind.HEAL],
	["nap_of_the_gods", 12, Spell.EffectKind.HEAL],
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

func _fresh_game_state():
	return get_node("/root/GameState")
