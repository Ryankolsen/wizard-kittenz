extends GutTest

# Character submenu Stats panel (#47, PRD #42). The submenu is reached
# from the PauseMenu root's Character button and renders the player's
# current stats live from GameState.current_character. A Back button
# returns to the root menu and an Inventory tab carries a "Coming soon"
# stub until the inventory system lands.
#
# These tests pin the contract from #47's acceptance criteria. They do
# not exercise the submenu visuals or layout — only that the named
# nodes exist and the labels carry the live stat values.

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_pause_menu_has_character_submenu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var submenu = scene.find_child("CharacterSubmenu", true, false)
	assert_not_null(submenu, "pause_menu.tscn must contain a node named CharacterSubmenu")
	scene.free()

func test_stats_panel_shows_level():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Pixel")
	c.level = 7
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_character_submenu()
	var label = scene.find_child("LevelLabel", true, false) as Label
	assert_not_null(label)
	assert_true(label.text.contains("7"), "level label must show current level")
	gs.clear()

func test_stats_panel_shows_hp():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.hp = 18
	c.max_hp = 30
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_character_submenu()
	var label = scene.find_child("HPLabel", true, false) as Label
	assert_not_null(label)
	assert_true(label.text.contains("18"), "HP label must show current HP")
	gs.clear()

func test_inventory_tab_has_equipment_panel():
	# Stub label was replaced by the EquipmentTabPanel in issue #82. The
	# InventoryTab node now carries the EquipmentTabPanel script and
	# renders Equipped / Bag sections on inventory-tab press.
	var gs := get_node("/root/GameState")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN))
	gs.item_inventory = ItemInventory.new()
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_character_submenu()
	var inv_btn := scene.find_child("InventoryTabButton", true, false) as Button
	assert_not_null(inv_btn)
	inv_btn.pressed.emit()
	var tab := scene.find_child("InventoryTab", true, false)
	assert_not_null(tab, "InventoryTab node must exist")
	var section := scene.find_child("Section_Equipped", true, false) as Label
	assert_not_null(section, "Equipment panel must render an Equipped section")
	gs.clear()

func test_character_button_is_enabled():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var btn = scene.find_child("Character", true, false) as Button
	assert_not_null(btn, "PauseMenu root must have a Character button")
	assert_false(btn.disabled, "Character button must be enabled in walking skeleton's successor")
	scene.free()

func test_character_button_opens_submenu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	var btn = scene.find_child("Character", true, false) as Button
	assert_not_null(btn)
	btn.pressed.emit()
	var submenu = scene.find_child("CharacterSubmenu", true, false) as Control
	assert_true(submenu.visible, "pressing Character must show the CharacterSubmenu")

func test_back_returns_to_root_menu():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open()
	scene.open_character_submenu()
	var back = scene.find_child("Back", true, false) as Button
	assert_not_null(back, "CharacterSubmenu must have a Back button")
	back.pressed.emit()
	var submenu = scene.find_child("CharacterSubmenu", true, false) as Control
	assert_false(submenu.visible, "CharacterSubmenu must hide on Back")
	var main = scene.find_child("MainMenu", true, false) as Control
	assert_not_null(main, "PauseMenu must expose a MainMenu container so Back can re-show it")
	assert_true(main.visible, "MainMenu must be visible again after Back")

func test_class_label_shows_character_class():
	var gs := get_node("/root/GameState")
	gs.set_character(CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Pixel"))
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_character_submenu()
	var label = scene.find_child("ClassLabel", true, false) as Label
	assert_not_null(label, "CharacterSubmenu must have a ClassLabel node")
	assert_eq(label.text, "Wizard kitten", "ClassLabel must show the character class name")
	gs.clear()

func test_stats_panel_shows_attack_defense_speed():
	var gs := get_node("/root/GameState")
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	c.attack = 9
	c.defense = 4
	c.speed = 88.0
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	scene.open_character_submenu()
	var atk = scene.find_child("ATKLabel", true, false) as Label
	var dfn = scene.find_child("DEFLabel", true, false) as Label
	var spd = scene.find_child("SPDLabel", true, false) as Label
	assert_not_null(atk)
	assert_not_null(dfn)
	assert_not_null(spd)
	assert_true(atk.text.contains("9"), "ATK label must show current attack")
	assert_true(dfn.text.contains("4"), "DEF label must show current defense")
	assert_true(spd.text.contains("88"), "SPD label must show current speed")
	gs.clear()
