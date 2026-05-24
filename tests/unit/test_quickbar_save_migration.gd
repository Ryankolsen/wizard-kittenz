extends GutTest

# Slice 5 of PRD #210: legacy save migration. A save written before this slice
# has no `quickbar_slots` key. On first load we auto-fill from the tree's
# unlocked spells in tree order, persist the result on the next save, and
# never re-migrate on subsequent loads (manual swaps stick).

func _wizard_tree() -> SkillTree:
	# Hairball + Catnip unlocked, Whisker NOT unlocked — pins the migration's
	# tree-order walk to a deterministic two-slot fill.
	var t := SkillTree.make_wizard_kitten_tree()
	t.unlock("hairball_hex")
	t.unlock("catnip_curse")
	return t

func _legacy_save_dict() -> Dictionary:
	# Mirrors a save written before quickbar_slots existed: every other field
	# present, no quickbar_slots key. Mirrors the shape KittenSaveData.to_dict
	# produced pre-slice-5.
	return {
		"character_name": "Whiskers",
		"character_class": int(CharacterData.CharacterClass.WIZARD_KITTEN),
		"level": 3,
		"xp": 0,
		"hp": 30,
		"max_hp": 30,
		"magic_points": 10,
		"max_mp": 10,
		"unlocked_skill_ids": ["hairball_hex", "catnip_curse"],
	}

func test_load_legacy_save_without_quickbar_field_auto_fills():
	var loaded := KittenSaveData.from_dict(_legacy_save_dict())
	var qb := loaded.to_quickbar(_wizard_tree())
	assert_not_null(qb.get_slot(1), "slot 1 should be auto-filled from tree order")
	assert_eq(qb.get_slot(1).id, "hairball_hex",
		"first unlocked spell in tree order should land in slot 1")
	assert_not_null(qb.get_slot(2), "slot 2 should be auto-filled from tree order")
	assert_eq(qb.get_slot(2).id, "catnip_curse",
		"second unlocked spell in tree order should land in slot 2")
	assert_null(qb.get_slot(3), "no third spell unlocked — slot 3 must stay empty")
	assert_null(qb.get_slot(4), "no fourth spell unlocked — slot 4 must stay empty")

func test_legacy_migration_persists_to_next_save():
	var loaded := KittenSaveData.from_dict(_legacy_save_dict())
	var qb := loaded.to_quickbar(_wizard_tree())
	# Re-serialize via from_character now that the migrated qb is in hand;
	# this is the path GameState/SaveManager would take on the next save.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var resaved := KittenSaveData.from_character(
		c, _wizard_tree(), null, null, null, null, {}, null, null, null, qb
	)
	var resaved_dict := resaved.to_dict()
	assert_true(resaved_dict.has("quickbar_slots"),
		"next save must include the quickbar_slots key so migration won't re-run")
	var slots = resaved_dict["quickbar_slots"]
	assert_eq(slots[0], "hairball_hex", "slot 1 id persists in the new save")
	assert_eq(slots[1], "catnip_curse", "slot 2 id persists in the new save")
	assert_eq(str(slots[2]), "", "slot 3 serializes as empty string")
	assert_eq(str(slots[3]), "", "slot 4 serializes as empty string")

func test_migration_does_not_rerun_on_subsequent_load():
	# Walk the full cycle: legacy load -> migrate -> manual swap -> re-save ->
	# re-load -> verify the manual swap survived (migration did NOT rerun).
	var loaded := KittenSaveData.from_dict(_legacy_save_dict())
	var qb := loaded.to_quickbar(_wizard_tree())
	# Manual swap: move Whisker Bolt into slot 1 (over hairball). Unlock it
	# on the live tree so the assignment is valid.
	var tree2 := _wizard_tree()
	tree2.unlock("whisker_bolt")
	qb.assign(1, tree2.find("whisker_bolt").spell)
	# Re-serialize (post-slice-5 path), then re-load and check slot 1.
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	var resaved := KittenSaveData.from_character(
		c, tree2, null, null, null, null, {}, null, null, null, qb
	)
	var dict2 := resaved.to_dict()
	var reloaded := KittenSaveData.from_dict(dict2)
	var qb_again := reloaded.to_quickbar(tree2)
	assert_eq(qb_again.get_slot(1).id, "whisker_bolt",
		"manual swap must survive the re-load — migration cannot re-fill from tree order")
