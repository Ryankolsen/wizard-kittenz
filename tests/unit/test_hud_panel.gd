extends GutTest

# Pins the HUD-stats panel wrapper: HP + XP bars live under a single
# StatsPanel PanelContainer with a StyleBoxFlat border so the HUD reads
# as a framed UI element instead of two floating bars. Visual surface
# only — no math is exercised here (the HP / XP ratio + label tests
# already cover the data path).

func test_hud_scene_has_panel_container():
	var scene = load("res://scenes/hud.tscn").instantiate()
	var panel = scene.find_child("StatsPanel", true, false)
	assert_not_null(panel, "hud.tscn must have a PanelContainer named StatsPanel")
	assert_true(panel is PanelContainer,
		"StatsPanel must be a PanelContainer")
	scene.free()

func test_hud_panel_contains_hp_bar():
	var scene = load("res://scenes/hud.tscn").instantiate()
	var panel = scene.find_child("StatsPanel", true, false)
	assert_not_null(panel)
	var hp_bar = panel.find_child("HPBar", true, false)
	assert_not_null(hp_bar, "HPBar must be a descendant of StatsPanel")
	scene.free()

func test_hud_panel_contains_xp_bar():
	var scene = load("res://scenes/hud.tscn").instantiate()
	var panel = scene.find_child("StatsPanel", true, false)
	assert_not_null(panel)
	var xp_bar = panel.find_child("XPBar", true, false)
	assert_not_null(xp_bar, "XPBar must be a descendant of StatsPanel")
	scene.free()

func test_hud_potion_belt_is_vertical_beside_quickbar():
	# PRD #384 follow-up: the desktop HUD potion belt stacks vertically next to
	# the magic grid (matching the mobile cluster), not horizontally below it.
	var scene = load("res://scenes/hud.tscn").instantiate()
	var belt = scene.find_child("PotionBeltHUD", true, false) as Control
	var quickbar = scene.find_child("QuickbarHUD", true, false) as Control
	assert_not_null(belt, "hud.tscn must have a PotionBeltHUD")
	assert_not_null(quickbar, "hud.tscn must have a QuickbarHUD")
	assert_eq(belt.orientation, PotionBeltHUD.Orientation.VERTICAL,
		"desktop potion belt must use vertical orientation")
	assert_true(belt.offset_right <= quickbar.offset_left,
		"potion column must sit to the left of the magic grid, not overlap it")
	assert_eq(belt.offset_top, quickbar.offset_top,
		"potion column must be top-aligned with the magic grid")
	scene.free()

func test_hud_panel_has_stylebox_with_border():
	var scene = load("res://scenes/hud.tscn").instantiate()
	var panel = scene.find_child("StatsPanel", true, false) as PanelContainer
	assert_not_null(panel)
	var stylebox = panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(stylebox, "StatsPanel must have a StyleBoxFlat theme override")
	var has_border: bool = (
		stylebox.border_width_top > 0 or
		stylebox.border_width_bottom > 0 or
		stylebox.border_width_left > 0 or
		stylebox.border_width_right > 0
	)
	assert_true(has_border, "StyleBoxFlat must have a non-zero border on at least one side")
	scene.free()
