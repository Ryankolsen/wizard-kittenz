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
