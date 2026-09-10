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

# assign_skills tutorial auto-trigger wiring (issue #607, PRD #596). Mirrors
# #606's equip_gear wiring tests: first Skills tab open with an empty
# tutorial_seen_topics fires the overlay, a second open after it's marked
# seen does not. Uses the shared _open_wizard_pause_menu helper, whose
# character (level 1 WIZARD_KITTEN) has hairball_hex auto-unlocked, so both
# tutorial steps have a live target to resolve.

func _find_tutorial_overlay(scene: Node) -> Node:
	return scene.find_child("TutorialOverlay", true, false)

func test_first_skills_tab_open_triggers_assign_skills_tutorial():
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = ["pause_menu", "equip_gear"]
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay, "the first Skills tab open must auto-show the assign_skills tutorial overlay")
	assert_true(overlay.visible, "the overlay must be open, not just instantiated")
	get_tree().paused = false

func test_only_first_skill_row_and_cluster_grouped():
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = ["pause_menu", "equip_gear", "assign_skills"]
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	# The wizard tree has more than one unlocked node once whisker_bolt is
	# flipped on, so a stale-duplicate-membership bug would show up here.
	GameState.skill_tree.unlock("whisker_bolt")
	scene._refresh_skills_panel()
	assert_eq(get_tree().get_nodes_in_group("tutorial_target_skill_node").size(), 1,
		"only the first skill row of a refresh may be in tutorial_target_skill_node")
	assert_eq(get_tree().get_nodes_in_group("tutorial_target_assign_slot").size(), 1,
		"only the first assign cluster of a refresh may be in tutorial_target_assign_slot")
	get_tree().paused = false

func test_no_unlocked_skills_falls_back_to_text_only():
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = ["pause_menu", "equip_gear"]
	var tree := SkillTree.new()
	var spell := Spell.make("locked_spell", "Locked Spell", Spell.EffectKind.DAMAGE, 5, 1.0)
	tree.add_node(SkillNode.make("locked_spell", "Locked Spell", spell, [], 1, 999))
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	gs.set_character(c)
	gs.skill_tree = tree
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.bind_quickbar(_QuickbarScript.new())
	scene.open_skills_panel()
	var overlay := _find_tutorial_overlay(scene)
	assert_not_null(overlay, "an empty unlocked-skill list must still open the overlay")
	var box := overlay.find_child("HighlightBox", true, false) as Control
	assert_false(box.visible,
		"with no unlocked skill nodes, the first step must fall back to a text-only bubble, not crash")
	get_tree().paused = false

func test_already_seen_assign_skills_does_not_retrigger():
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = ["pause_menu", "equip_gear", "assign_skills"]
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	assert_null(_find_tutorial_overlay(scene),
		"once seen, opening the Skills tab must not re-trigger the assign_skills tutorial")
	get_tree().paused = false

func test_repeated_refresh_does_not_grow_group_membership():
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = ["pause_menu", "equip_gear", "assign_skills"]
	var qb = _QuickbarScript.new()
	var scene = _open_wizard_pause_menu(qb)
	scene._refresh_skills_panel()
	scene._refresh_skills_panel()
	assert_eq(get_tree().get_nodes_in_group("tutorial_target_skill_node").size(), 1,
		"repeated refreshes must not grow tutorial_target_skill_node membership")
	assert_eq(get_tree().get_nodes_in_group("tutorial_target_assign_slot").size(), 1,
		"repeated refreshes must not grow tutorial_target_assign_slot membership")
	get_tree().paused = false
