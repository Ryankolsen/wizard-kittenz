extends GutTest

# Skills tab inside the Character submenu (#48 originally; behavior reshaped
# in #130 / PRD #124). Skills are no longer purchased — they auto-unlock
# when the character reaches the node's `level_required`. The panel pins
# the AC from #130:
#   - SkillsPanel node exists in the .tscn
#   - SkillPointsLabel reads live from GameState.current_character.skill_points
#     (skill points still exist; they're spent on stats elsewhere)
#   - Locked rows render "Unlocks at level X" — no buttons
#   - Unlocked rows render their name + an "Unlocked" status
#   - The list refreshes after a level-up so newly-eligible nodes flip
#   - A Skills tab button on the Character submenu switches the visible
#     panel from Stats to Skills

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
	var skills = scene.find_child("SkillsPanel", true, false) as Control
	var stats = scene.find_child("StatsPanel", true, false) as Control
	assert_true(stats.visible, "Stats tab must be the default landing tab")
	assert_false(skills.visible, "Skills tab must start hidden on submenu open")
	var btn = scene.find_child("SkillsTabButton", true, false) as Button
	btn.pressed.emit()
	assert_true(skills.visible, "pressing Skills tab must reveal SkillsPanel")
	assert_false(stats.visible, "Stats tab must hide when Skills is selected")
	gs.clear()

# #130 AC1: Battle Kitten level 1 sees "level 3" in the hissy_fit row label.
func test_locked_node_shows_level_required():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	var label := scene.find_child("SkillRowLabel_hissy_fit", true, false) as Label
	assert_not_null(label, "row label for locked hissy_fit must exist")
	assert_true(label.text.to_lower().contains("level 3"),
		"locked row must read 'Unlocks at level 3' (got: '%s')" % label.text)
	gs.clear()

# #130 AC2: an unlocked node (paw_smash, level_required=1) must NOT contain
# "Unlocks at" — the level-required text is only for locked rows.
func test_unlocked_node_has_no_unlocks_at_text():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	var label := scene.find_child("SkillRowLabel_paw_smash", true, false) as Label
	assert_not_null(label, "row label for unlocked paw_smash must exist")
	assert_false(label.text.to_lower().contains("unlocks at"),
		"unlocked row must NOT contain 'Unlocks at' (got: '%s')" % label.text)
	gs.clear()

# #130 AC3: a level-up that satisfies level_required flips the row from
# "Unlocks at level 3" to its unlocked display when the panel is refreshed.
func test_level_up_refresh_flips_locked_row():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	var label_before := scene.find_child("SkillRowLabel_hissy_fit", true, false) as Label
	assert_true(label_before.text.to_lower().contains("unlocks at level 3"),
		"precondition: hissy_fit starts locked at level 1")
	# Dump enough XP to push the character to level 3 and trigger the
	# level-gated auto-unlock pass. add_xp threads the tree through so the
	# checker fires on each crossed threshold.
	var xp_to_3 := 0
	for lvl in range(1, 3):
		xp_to_3 += ProgressionSystem.xp_to_next_level(lvl)
	ProgressionSystem.add_xp(c, xp_to_3, null, gs.skill_tree)
	assert_eq(c.level, 3, "precondition: XP dump landed at level 3")
	scene.open_skills_panel()
	var label_after := scene.find_child("SkillRowLabel_hissy_fit", true, false) as Label
	assert_false(label_after.text.to_lower().contains("unlocks at"),
		"after level-up to 3, hissy_fit row must drop the 'Unlocks at' text (got: '%s')" % label_after.text)
	gs.clear()

# #130 AC4: skills are no longer purchased — no Unlock buttons anywhere
# in the rendered SkillsList.
func test_no_unlock_buttons_in_skills_list():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_skills_panel()
	var list := scene.find_child("SkillsList", true, false) as VBoxContainer
	assert_not_null(list)
	for row in list.get_children():
		for child in row.get_children():
			if child is Button:
				var btn := child as Button
				assert_false(btn.text.to_lower().contains("unlock"),
					"no row may carry an 'Unlock' button (found: '%s')" % btn.text)
	gs.clear()
