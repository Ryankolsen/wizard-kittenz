extends GutTest

# Issue #125: SkillNode.level_required + Spell.EffectKind.HEAL/TAUNT.

func test_skill_node_level_required_explicit():
	var spell := Spell.make("paw_smash", "Paw Smash", Spell.EffectKind.DAMAGE, 1, 1.0)
	var node := SkillNode.make("paw_smash", "Paw Smash", spell, [], 0, 1)
	assert_eq(node.level_required, 1, "level_required set from explicit argument")

func test_skill_node_level_required_default_when_omitted():
	var spell := Spell.make("paw_smash", "Paw Smash", Spell.EffectKind.DAMAGE, 1, 1.0)
	var node := SkillNode.make("paw_smash", "Paw Smash", spell, [], 1)
	assert_eq(node.level_required, 1, "level_required defaults to 1")

func test_skill_node_level_required_can_be_higher():
	var spell := Spell.make("nap_gods", "Nap of the Gods", Spell.EffectKind.DAMAGE, 1, 1.0)
	var node := SkillNode.make("nap_gods", "Nap of the Gods", spell, [], 1, 12)
	assert_eq(node.level_required, 12)

func test_effect_kind_heal_and_taunt_exist_and_are_distinct():
	var kinds := [
		Spell.EffectKind.DAMAGE,
		Spell.EffectKind.AREA,
		Spell.EffectKind.BUFF,
		Spell.EffectKind.HEAL,
		Spell.EffectKind.TAUNT,
	]
	var unique := {}
	for k in kinds:
		unique[k] = true
	assert_eq(unique.size(), kinds.size(), "all EffectKind values are distinct")

func test_existing_trees_default_level_required_to_1():
	var trees := [
		SkillTree.make_mage_tree(),
		SkillTree.make_thief_tree(),
		SkillTree.make_ninja_tree(),
	]
	for tree in trees:
		for node in tree.nodes:
			assert_eq(node.level_required, 1, "existing tree node defaults level_required to 1")
