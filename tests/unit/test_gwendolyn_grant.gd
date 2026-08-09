extends GutTest

# GwendolynGrant (PRD #474 / issue #475). Independent of the achievement-claim
# flow: a character named "Gwendolyn" receives the summon_gwendolyn skill
# node directly. Mirrors AchievementService's TOME active/inactive-slot
# grant pattern (see test_achievement_service.gd's TOME claim tests).

func _make_tree() -> SkillTree:
	var t := SkillTree.new()
	var spell := Spell.make("summon_gwendolyn", "Summon Gwendolyn", Spell.EffectKind.BUFF, 0, 15.0)
	t.add_node(SkillNode.make("summon_gwendolyn", "Summon Gwendolyn", spell, [], 1, 999))
	return t

func test_grant_to_active_unlocks_node_and_fills_quickbar():
	var tree := _make_tree()
	var qb := Quickbar.new()
	GwendolynGrant.grant_to_active(tree, qb)
	assert_true(tree.is_unlocked("summon_gwendolyn"))
	assert_eq(qb.get_slot(1).id, "summon_gwendolyn", "spell auto-fills the lowest empty slot")

func test_grant_to_active_twice_does_not_duplicate_quickbar_assignment():
	var tree := _make_tree()
	var qb := Quickbar.new()
	GwendolynGrant.grant_to_active(tree, qb)
	GwendolynGrant.grant_to_active(tree, qb)
	assert_eq(qb.get_slot(1).id, "summon_gwendolyn")
	assert_null(qb.get_slot(2), "no duplicate assignment into a second slot")

func test_grant_to_slot_mirrors_into_persisted_slot_data():
	var slot := CharacterSlotData.new()
	GwendolynGrant.grant_to_slot(slot)
	assert_true(slot.unlocked_skill_ids.has("summon_gwendolyn"))
	assert_true(slot.quickbar_slots.has("summon_gwendolyn"))

func test_grant_to_slot_twice_does_not_duplicate():
	var slot := CharacterSlotData.new()
	GwendolynGrant.grant_to_slot(slot)
	GwendolynGrant.grant_to_slot(slot)
	var count := 0
	for id in slot.unlocked_skill_ids:
		if id == "summon_gwendolyn":
			count += 1
	assert_eq(count, 1, "unlocked_skill_ids is not duplicated")
	var slot_count := 0
	for id in slot.quickbar_slots:
		if id == "summon_gwendolyn":
			slot_count += 1
	assert_eq(slot_count, 1, "quickbar_slots is not duplicated")

func test_grant_to_slot_null_is_safe_no_op():
	GwendolynGrant.grant_to_slot(null)
	assert_true(true, "null slot must not crash")
