extends GutTest

# Slice 4 of PRD #210. The Skills tab gains per-row `[1] [2] [3] [4]` buttons
# that route through Quickbar.assign / .unassign so the player can bind any
# unlocked spell to a quickbar slot without leaving the pause menu.

const _QuickbarScript := preload("res://scripts/character/quickbar.gd")

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func _open_wizard_pause_menu(qb):
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.bind_quickbar(qb)
	scene.open_skills_panel()
	return scene

func test_unlocked_skill_row_has_assign_buttons():
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	var row = scene.find_child("SkillRow_hairball_hex", true, false)
	assert_not_null(row, "unlocked hairball_hex row must exist")
	for n in range(1, 5):
		var btn = scene.find_child("assign_slot_%d" % n, true, false) as Button
		assert_not_null(btn, "assign_slot_%d must be present on the Hairball row" % n)
		assert_eq(btn.get_parent().get_parent().name, StringName("SkillRow_hairball_hex"),
			"assign_slot_%d must live inside the Hairball row" % n)

func test_locked_skill_row_has_no_assign_buttons():
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	var row = scene.find_child("SkillRow_catnip_curse", true, false)
	assert_not_null(row, "locked catnip_curse row must exist")
	for n in range(1, 5):
		# Locked rows must not have any assign controls — search the row
		# subtree directly so a stray button on a different row doesn't pass
		# this assertion by accident.
		var btn = row.find_child("assign_slot_%d" % n, true, false)
		assert_null(btn, "locked row must not have assign_slot_%d" % n)

func test_tap_assign_slot_2_assigns_spell():
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	var row = scene.find_child("SkillRow_hairball_hex", true, false)
	var btn = row.find_child("assign_slot_2", true, false) as Button
	btn.pressed.emit()
	var hairball := GameState.skill_tree.find("hairball_hex").spell
	assert_eq(qb.get_slot(2), hairball,
		"pressing assign_slot_2 on Hairball row must assign Hairball Hex to slot 2")

func test_assigned_slot_button_is_highlighted():
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	var row = scene.find_child("SkillRow_hairball_hex", true, false)
	(row.find_child("assign_slot_2", true, false) as Button).pressed.emit()
	# Panel refresh rebuilds the row, so re-look-up after the assignment.
	row = scene.find_child("SkillRow_hairball_hex", true, false)
	assert_true((row.find_child("assign_slot_2", true, false) as Button).button_pressed,
		"slot 2 button must be highlighted (checked) after assignment")
	for other in [1, 3, 4]:
		assert_false((row.find_child("assign_slot_%d" % other, true, false) as Button).button_pressed,
			"slot %d button must not be highlighted" % other)

func test_retap_same_slot_unassigns():
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	var row = scene.find_child("SkillRow_hairball_hex", true, false)
	(row.find_child("assign_slot_2", true, false) as Button).pressed.emit()
	row = scene.find_child("SkillRow_hairball_hex", true, false)
	(row.find_child("assign_slot_2", true, false) as Button).pressed.emit()
	assert_null(qb.get_slot(2),
		"re-tapping the currently-assigned slot must unassign the spell")

func test_assigning_to_occupied_slot_swaps():
	# Wizard tree has whisker_bolt locked at level 5 — flip it unlocked
	# directly rather than dumping XP. The test only cares about the row
	# being eligible for assignment controls.
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	var tree := GameState.skill_tree
	tree.unlock("whisker_bolt")
	scene.open_skills_panel()
	var hairball := tree.find("hairball_hex").spell
	var whisker := tree.find("whisker_bolt").spell
	# Seed: hairball in slot 1, whisker in slot 2.
	qb.assign(1, hairball)
	qb.assign(2, whisker)
	scene.open_skills_panel()
	# Press slot 1 on the whisker row → should swap so slot 1 = whisker,
	# slot 2 = hairball.
	var whisker_row = scene.find_child("SkillRow_whisker_bolt", true, false)
	(whisker_row.find_child("assign_slot_1", true, false) as Button).pressed.emit()
	assert_eq(qb.get_slot(1), whisker, "slot 1 must hold whisker after swap")
	assert_eq(qb.get_slot(2), hairball, "slot 2 must hold hairball after swap")
	var hairball_row = scene.find_child("SkillRow_hairball_hex", true, false)
	assert_true((hairball_row.find_child("assign_slot_2", true, false) as Button).button_pressed,
		"hairball row's slot 2 button must be highlighted post-swap")
	whisker_row = scene.find_child("SkillRow_whisker_bolt", true, false)
	assert_true((whisker_row.find_child("assign_slot_1", true, false) as Button).button_pressed,
		"whisker row's slot 1 button must be highlighted post-swap")
