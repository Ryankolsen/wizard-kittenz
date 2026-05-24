extends GutTest

# Slice 1 of PRD #210: Quickbar data class + InputMap cast_slot_1..cast_slot_4.

const _KEY_1 := 49
const _KEY_Q := 81
const _KEY_F := 70

func _wizard_tree() -> SkillTree:
	return SkillTree.make_wizard_kitten_tree()

func _spell(tree: SkillTree, id: String) -> Spell:
	return tree.find(id).spell

func test_assign_places_spell_in_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var hairball := _spell(tree, "hairball_hex")
	qb.assign(1, hairball)
	assert_eq(qb.get_slot(1), hairball)

func test_assign_same_spell_to_new_slot_swaps():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	qb.assign(1, a)
	qb.assign(2, a)
	assert_null(qb.get_slot(1))
	assert_eq(qb.get_slot(2), a)

func test_assign_over_occupied_slot_swaps_occupants():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	var b := _spell(tree, "catnip_curse")
	qb.assign(1, a)
	qb.assign(2, b)
	qb.assign(2, a)
	assert_eq(qb.get_slot(1), b)
	assert_eq(qb.get_slot(2), a)

func test_unassign_clears_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	qb.assign(1, a)
	qb.unassign(1)
	assert_null(qb.get_slot(1))

func test_on_spell_unlocked_fills_lowest_empty_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	var b := _spell(tree, "catnip_curse")
	qb.assign(1, a)
	qb.on_spell_unlocked(b)
	assert_eq(qb.get_slot(2), b)

func test_on_spell_unlocked_noop_when_full():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	qb.assign(1, _spell(tree, "hairball_hex"))
	qb.assign(2, _spell(tree, "catnip_curse"))
	qb.assign(3, _spell(tree, "whisker_bolt"))
	qb.assign(4, _spell(tree, "litter_storm"))
	var arcane := _spell(tree, "arcane_purr")
	qb.on_spell_unlocked(arcane)
	for i in range(1, Quickbar.SLOT_COUNT + 1):
		assert_ne(qb.get_slot(i), arcane)

func test_on_spell_unlocked_noop_when_already_in_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	qb.assign(2, a)
	qb.on_spell_unlocked(a)
	assert_null(qb.get_slot(1))
	assert_eq(qb.get_slot(2), a)
	assert_null(qb.get_slot(3))
	assert_null(qb.get_slot(4))

func test_fire_slot_empty_returns_false():
	var qb := Quickbar.new()
	watch_signals(qb)
	assert_false(qb.fire_slot(1, null))
	assert_signal_not_emitted(qb, "slot_fired")

func test_fire_slot_calls_spell_cast():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	# Make MP cost trivially affordable: the spell carries mp_cost > 0, give a
	# caster with enough magic_points so cast() succeeds.
	var caster := _StubCaster.new()
	caster.magic_points = 999
	caster.hp = 999
	qb.assign(1, a)
	watch_signals(qb)
	assert_true(qb.fire_slot(1, caster))
	assert_signal_emitted_with_parameters(qb, "slot_fired", [1])

func test_serialize_deserialize_preserves_assignments():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	var c := _spell(tree, "whisker_bolt")
	qb.assign(1, a)
	qb.assign(3, c)
	var dict := qb.serialize()
	var fresh_tree := _wizard_tree()
	var qb2 := Quickbar.new()
	qb2.deserialize(dict, fresh_tree)
	assert_eq(qb2.get_slot(1).id, "hairball_hex")
	assert_null(qb2.get_slot(2))
	assert_eq(qb2.get_slot(3).id, "whisker_bolt")
	assert_null(qb2.get_slot(4))

func test_inputmap_has_cast_slot_actions():
	for i in range(1, 5):
		var name := "cast_slot_%d" % i
		assert_true(InputMap.has_action(name), "InputMap missing %s" % name)
	var keys := {}
	for ev in InputMap.action_get_events("cast_slot_1"):
		if ev is InputEventKey:
			keys[ev.keycode] = true
	assert_true(keys.has(_KEY_1), "cast_slot_1 missing key 1")
	assert_true(keys.has(_KEY_Q), "cast_slot_1 missing key Q")
	assert_true(keys.has(_KEY_F), "cast_slot_1 missing key F")

class _StubCaster:
	var magic_points: int = 0
	var hp: int = 100
