extends GutTest

# TutorialTopicMenu: help-icon topic picker popup (#610, PRD #596). Pure
# "pick one of N" UI -- it enumerates TutorialCatalog.topic_ids() into
# labeled rows and emits topic_selected(topic_id) on click. It never calls
# TutorialSequencer/TutorialProgress/GameState itself; the caller (a later
# wiring slice) acts on the emitted id.
#
# is_touch is passed into populate() explicitly (mirroring TutorialTrigger.
# should_trigger's is_touch parameter) so tests can drive both platform
# branches without depending on the real OS.has_feature() result.

func test_touch_shows_all_seven_topics():
	var menu = load("res://scenes/tutorial_topic_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.populate(true)
	var rows: Array = menu.get_topic_rows()
	assert_eq(rows.size(), 7, "touch platform must show all 7 topics")
	var expected := {
		"main_menu": "Main Menu",
		"movement_attack": "Movement & Attack",
		"pause_menu": "Pause Menu",
		"equip_gear": "Equipping Gear",
		"assign_skills": "Assigning Skills",
		"tavern": "The Tavern",
		"achievements": "Achievements",
	}
	for row in rows:
		var btn := row as Button
		assert_not_null(btn, "each topic row must be a Button")

func test_row_click_emits_topic_selected_with_correct_id():
	var menu = load("res://scenes/tutorial_topic_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.populate(true)
	watch_signals(menu)
	var tavern_row := menu.get_topic_row("tavern") as Button
	assert_not_null(tavern_row, "tavern row must exist")
	tavern_row.pressed.emit()
	assert_signal_emitted_with_parameters(menu, "topic_selected", ["tavern"])

func test_desktop_excludes_movement_attack():
	var menu = load("res://scenes/tutorial_topic_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.populate(false)
	var rows: Array = menu.get_topic_rows()
	assert_eq(rows.size(), 6, "desktop must exclude movement_attack, leaving 6 rows")
	assert_null(menu.get_topic_row("movement_attack"),
		"desktop must not render a movement_attack row")

func test_close_button_emits_closed_not_topic_selected():
	var menu = load("res://scenes/tutorial_topic_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.populate(true)
	watch_signals(menu)
	var close_btn := menu.find_child("CloseButton", true, false) as Button
	assert_not_null(close_btn, "CloseButton must exist")
	close_btn.pressed.emit()
	assert_signal_emitted(menu, "closed")
	assert_signal_not_emitted(menu, "topic_selected")
