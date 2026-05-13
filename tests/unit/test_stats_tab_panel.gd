extends GutTest

# StatsTabPanel (#60, PRD #52). Pins the display contract: every
# allocatable stat from StatAllocator is rendered, "+" buttons gate on
# skill_points, evasion / crit_chance display as percent, and pressing
# "+" spends one point through StatAllocator and refreshes the panel.

func _mage_with_points(points: int) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.skill_points = points
	return c

func test_refresh_renders_unspent_points_label():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(3)
	panel.refresh(c)
	assert_eq(panel.get_unspent_label_text(), "Unspent points: 3")

func test_refresh_renders_zero_unspent_points():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(0)
	panel.refresh(c)
	assert_eq(panel.get_unspent_label_text(), "Unspent points: 0")

func test_plus_buttons_disabled_at_zero_points():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(0)
	panel.refresh(c)
	for stat in ["max_hp", "attack", "magic_attack", "defense", "evasion", "crit_chance", "luck"]:
		var btn := panel.get_plus_button(stat)
		assert_not_null(btn, "plus button for %s must exist" % stat)
		assert_true(btn.disabled, "plus button for %s must be disabled at 0 points" % stat)

func test_plus_buttons_enabled_with_points():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(1)
	panel.refresh(c)
	assert_false(panel.get_plus_button("attack").disabled,
		"plus button must enable when skill_points > 0")

func test_evasion_displays_as_percent():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(0)
	c.evasion = 0.15
	panel.refresh(c)
	assert_true(panel.get_stat_label("evasion").text.contains("15%"),
		"evasion 0.15 must render as 15%%, got %s" % panel.get_stat_label("evasion").text)

func test_crit_chance_displays_as_percent():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(0)
	c.crit_chance = 0.07
	panel.refresh(c)
	assert_true(panel.get_stat_label("crit_chance").text.contains("7%"),
		"crit_chance 0.07 must render as 7%%, got %s" % panel.get_stat_label("crit_chance").text)

func test_all_expanded_stat_rows_present():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	for stat in ["max_hp", "max_mp", "attack", "magic_attack", "defense",
			"magic_resistance", "speed", "dexterity", "evasion",
			"crit_chance", "luck", "regeneration"]:
		assert_not_null(panel.get_stat_label(stat), "stat row missing: %s" % stat)
		assert_not_null(panel.get_plus_button(stat), "plus button missing: %s" % stat)

func test_plus_press_spends_one_point_via_stat_allocator():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(2)
	var before_atk := c.attack
	panel.refresh(c)
	panel.get_plus_button("attack").pressed.emit()
	assert_eq(c.attack, before_atk + StatAllocator.INT_INCREMENTS["attack"],
		"plus press must apply the StatAllocator increment")
	assert_eq(c.skill_points, 1, "plus press must deduct one skill point")

func test_plus_press_refreshes_unspent_label():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(2)
	panel.refresh(c)
	panel.get_plus_button("attack").pressed.emit()
	assert_eq(panel.get_unspent_label_text(), "Unspent points: 1",
		"unspent label must refresh after a successful spend")

func test_plus_press_disables_buttons_when_points_hit_zero():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(1)
	panel.refresh(c)
	panel.get_plus_button("attack").pressed.emit()
	assert_true(panel.get_plus_button("attack").disabled,
		"plus buttons must disable once skill_points reaches 0")

func test_plus_press_on_max_hp_heals_by_increment():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(1)
	c.hp = 5
	var before_max := c.max_hp
	panel.refresh(c)
	panel.get_plus_button("max_hp").pressed.emit()
	assert_eq(c.max_hp, before_max + StatAllocator.INT_INCREMENTS["max_hp"])
	assert_eq(c.hp, 5 + StatAllocator.INT_INCREMENTS["max_hp"],
		"max_hp spend must also heal hp by the same delta (matches StatAllocator)")

func test_refresh_null_character_falls_back_to_em_dash():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	panel.refresh(null)
	assert_eq(panel.get_unspent_label_text(), "Unspent points: 0")
	assert_eq(panel.get_stat_label("attack").text, "—",
		"null character must render placeholders, not zeros")
	assert_true(panel.get_plus_button("attack").disabled,
		"plus buttons must disable with no character")

func test_allocated_signal_emits_on_successful_press():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(1)
	panel.refresh(c)
	watch_signals(panel)
	panel.get_plus_button("attack").pressed.emit()
	assert_signal_emitted_with_parameters(panel, "allocated", ["attack"])

func test_pause_menu_stats_panel_uses_stats_tab_panel_script():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	var panel = scene.find_child("StatsPanel", true, false)
	assert_not_null(panel, "StatsPanel node must exist in pause_menu.tscn")
	assert_true(panel is StatsTabPanel,
		"StatsPanel must have the StatsTabPanel script attached")

func test_pause_menu_open_character_submenu_refreshes_panel():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.skill_points = 4
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_character_submenu()
	var panel = scene.find_child("StatsPanel", true, false) as StatsTabPanel
	assert_eq(panel.get_unspent_label_text(), "Unspent points: 4")
	gs.clear()

# --- Continue button (PRD #52 / #61 dungeon-transition flow) ---------------

func test_continue_button_hidden_by_default():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var btn := panel.get_continue_button()
	assert_not_null(btn, "ContinueButton must exist on the panel")
	assert_false(btn.visible, "ContinueButton is hidden by default")

func test_set_continue_visible_toggles_button():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	panel.set_continue_visible(true)
	assert_true(panel.get_continue_button().visible)
	panel.set_continue_visible(false)
	assert_false(panel.get_continue_button().visible)

func test_continue_button_always_enabled_regardless_of_points():
	# AC: if skill_points == 0 the Continue button is still available.
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	var c := _mage_with_points(0)
	panel.refresh(c)
	panel.set_continue_visible(true)
	var btn := panel.get_continue_button()
	assert_false(btn.disabled,
		"ContinueButton must NOT be gated by skill_points (Continue must be "
		+ "immediately available even at 0 unspent points)")

func test_continue_button_press_emits_signal():
	var panel := StatsTabPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)
	panel.set_continue_visible(true)
	panel.get_continue_button().emit_signal("pressed")
	assert_signal_emitted(panel, "continue_pressed")

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()
