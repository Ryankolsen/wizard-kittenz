extends GutTest

# Slice 5 of PRD #210: KittenSaveData round-trips Quickbar slot bindings.

func _wizard_tree() -> SkillTree:
	var t := SkillTree.make_wizard_kitten_tree()
	t.unlock("hairball_hex")
	t.unlock("catnip_curse")
	return t

func _wizard_data() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)

func test_character_save_round_trip_preserves_quickbar():
	var tree := _wizard_tree()
	var hairball := tree.find("hairball_hex").spell
	var qb := Quickbar.new()
	qb.assign(2, hairball)
	var c := _wizard_data()
	var save_data := KittenSaveData.from_character(
		c, tree, null, null, null, null, {}, null, null, null, qb
	)
	var dict := save_data.to_dict()
	var loaded := KittenSaveData.from_dict(dict)
	var qb2 := loaded.to_quickbar(_wizard_tree())
	assert_null(qb2.get_slot(1), "slot 1 should be empty after round-trip")
	assert_not_null(qb2.get_slot(2), "slot 2 should have the assigned spell")
	assert_eq(qb2.get_slot(2).id, "hairball_hex",
		"slot 2 spell id should round-trip through serialize/deserialize")
