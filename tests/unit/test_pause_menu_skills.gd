extends GutTest

# Skills tab inside the Character submenu (#48, PRD #42). Pins the
# acceptance criteria from #48:
#   - SkillsPanel node exists in the .tscn
#   - SkillPointsLabel reads live from GameState.current_character.skill_points
#   - try_unlock_skill mutates skill_points + tree state via SkillTreeManager
#   - try_unlock_skill with insufficient points is a no-op (no crash, no
#     state change)
#   - A Skills tab button on the Character submenu switches the visible
#     panel from Stats to Skills
#
# The per-node row visuals (locked vs unlocked text) are tested as a
# label-text contract — a future polish pass can swap in icons without
# breaking these tests so long as the "Locked" / "Unlocked" tokens stay
# in the label text.

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_pause_menu_has_skills_panel():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var panel = scene.find_child("SkillsPanel", true, false)
	assert_not_null(panel, "pause_menu.tscn must contain a node named SkillsPanel")
	scene.free()

func test_skills_panel_shows_skill_points():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 3
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	var label = scene.find_child("SkillPointsLabel", true, false) as Label
	assert_not_null(label)
	assert_true(label.text.contains("3"), "label must show available skill points")
	gs.clear()

func test_unlock_node_decrements_skill_points():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 2
	gs.set_character(c)
	gs.skill_tree = SkillTree.make_mage_tree()
	var first_id: String = gs.skill_tree.all_nodes()[0].id
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	scene.try_unlock_skill(first_id)
	assert_eq(gs.current_character.skill_points, 1,
		"spending a skill point must decrement skill_points")
	assert_true(gs.skill_tree.is_unlocked(first_id), "node must be marked unlocked")
	gs.clear()

func test_unlock_with_no_points_is_noop():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 0
	gs.set_character(c)
	gs.skill_tree = SkillTree.make_mage_tree()
	var first_id: String = gs.skill_tree.all_nodes()[0].id
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	scene.try_unlock_skill(first_id)
	assert_eq(gs.current_character.skill_points, 0, "no points spent")
	assert_false(gs.skill_tree.is_unlocked(first_id), "node must remain locked")
	gs.clear()

func test_skills_tab_button_exists():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var btn = scene.find_child("SkillsTabButton", true, false) as Button
	assert_not_null(btn, "Character submenu must have a SkillsTabButton")
	scene.free()

func test_skills_tab_button_switches_to_skills():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_character_submenu()
	# Stats is the default tab — Skills should start hidden.
	var skills = scene.find_child("SkillsPanel", true, false) as Control
	var stats = scene.find_child("StatsPanel", true, false) as Control
	assert_true(stats.visible, "Stats tab must be the default landing tab")
	assert_false(skills.visible, "Skills tab must start hidden on submenu open")
	var btn = scene.find_child("SkillsTabButton", true, false) as Button
	btn.pressed.emit()
	assert_true(skills.visible, "pressing Skills tab must reveal SkillsPanel")
	assert_false(stats.visible, "Stats tab must hide when Skills is selected")
	gs.clear()

func test_unlocked_skill_label_says_unlocked():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 1
	gs.set_character(c)
	gs.skill_tree = SkillTree.make_mage_tree()
	var first_id: String = gs.skill_tree.all_nodes()[0].id
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	scene.try_unlock_skill(first_id)
	var label = scene.find_child("SkillRowLabel_%s" % first_id, true, false) as Label
	assert_not_null(label, "row label for unlocked node must exist")
	assert_true(label.text.to_lower().contains("unlocked"),
		"unlocked row label must read 'Unlocked' (visually distinct from Locked)")
	gs.clear()

func test_locked_skill_label_says_locked():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 0
	gs.set_character(c)
	gs.skill_tree = SkillTree.make_mage_tree()
	var first_id: String = gs.skill_tree.all_nodes()[0].id
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	var label = scene.find_child("SkillRowLabel_%s" % first_id, true, false) as Label
	assert_not_null(label, "row label for locked node must exist")
	# "Locked" appears in the locked status — and "Unlocked" must NOT match
	# (the label text is exactly "<name> — Locked" for locked rows).
	assert_true(label.text.contains("Locked"),
		"locked row label must include 'Locked'")
	assert_false(label.text.to_lower().contains("unlocked"),
		"locked row label must NOT contain 'unlocked'")
	gs.clear()

func test_unlock_unknown_id_is_safe():
	# Defensive: try_unlock_skill against an id that doesn't exist in the
	# tree returns false without crashing — protects against UI / save
	# desync (saved skill ids reference a renamed node).
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.skill_points = 5
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	var ok: bool = scene.try_unlock_skill("not_a_real_skill")
	assert_false(ok, "unknown id must return false")
	assert_eq(gs.current_character.skill_points, 5, "no points spent on unknown id")
	gs.clear()
