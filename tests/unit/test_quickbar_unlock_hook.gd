extends GutTest

# Slice 5 of PRD #210: level-up auto-unlocks route through Quickbar so newly-
# unlocked spells fill the lowest empty slot without manual reassignment.

func _wizard_tree() -> SkillTree:
	var t := SkillTree.make_wizard_kitten_tree()
	t.unlock("hairball_hex")
	return t

func _wizard_data() -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.level = 1
	c.xp = 0
	return c

func test_level_up_unlock_auto_fills_quickbar():
	# Wizard at level 1 with Hairball already in slot 1. Catnip Curse unlocks
	# at level 3 — leveling up there should auto-fill slot 2.
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	qb.assign(1, tree.find("hairball_hex").spell)
	var c := _wizard_data()
	# Dump enough XP to cross levels 1 -> 2 -> 3 in one call.
	var xp_needed := 0
	for lvl in [1, 2]:
		xp_needed += ProgressionSystem.xp_to_next_level(lvl)
	ProgressionSystem.add_xp(c, xp_needed, null, tree, qb)
	assert_eq(c.level, 3, "wizard should reach level 3")
	assert_not_null(qb.get_slot(2), "slot 2 should be auto-filled by the unlock")
	assert_eq(qb.get_slot(2).id, "catnip_curse",
		"the newly-unlocked level-3 spell should occupy slot 2")

func test_level_up_unlock_noop_when_quickbar_full():
	# Pre-fill all 4 slots; a 5th unlock must not displace anything.
	var tree := _wizard_tree()
	tree.unlock("catnip_curse")
	tree.unlock("whisker_bolt")
	tree.unlock("litter_storm")
	var qb := Quickbar.new()
	qb.assign(1, tree.find("hairball_hex").spell)
	qb.assign(2, tree.find("catnip_curse").spell)
	qb.assign(3, tree.find("whisker_bolt").spell)
	qb.assign(4, tree.find("litter_storm").spell)
	var c := _wizard_data()
	# Skip directly to level 12 so arcane_purr unlocks.
	var xp_needed := 0
	for lvl in range(1, 12):
		xp_needed += ProgressionSystem.xp_to_next_level(lvl)
	ProgressionSystem.add_xp(c, xp_needed, null, tree, qb)
	assert_eq(c.level, 12, "wizard should reach level 12")
	# All four slots unchanged — arcane_purr was unlocked but had no room.
	assert_eq(qb.get_slot(1).id, "hairball_hex")
	assert_eq(qb.get_slot(2).id, "catnip_curse")
	assert_eq(qb.get_slot(3).id, "whisker_bolt")
	assert_eq(qb.get_slot(4).id, "litter_storm")

func test_unlock_idempotent_when_spell_already_in_slot():
	# Hairball already in slot 1. on_spell_unlocked must not duplicate or
	# shuffle when the unlock pass re-encounters the same spell.
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var hairball := tree.find("hairball_hex").spell
	qb.assign(1, hairball)
	# Direct call to the hook surface — the same on_spell_unlocked that
	# add_xp invokes for newly-unlocked ids.
	qb.on_spell_unlocked(hairball)
	assert_eq(qb.get_slot(1), hairball,
		"already-assigned spell should remain in its original slot")
	assert_null(qb.get_slot(2),
		"re-emitting the unlock for an assigned spell must not fill another slot")
