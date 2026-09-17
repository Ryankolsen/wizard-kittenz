extends GutTest

# Static tutorial content catalog (PRD #596, issue #597). Pure-data tests --
# no scene tree, no nodes. Mirrors test_achievement_catalog's shape of
# asserting exact text/target_group/touch_only per entry.

func test_topic_ids_returns_all_fifteen_in_order():
	assert_eq(TutorialCatalog.topic_ids(), ["main_menu", "multiplayer_button", "shop_button", "movement_attack", "pause_menu", "stats_tab", "skills_tab", "inventory_tab", "items_tab", "achievements_tab", "equip_gear", "assign_skills", "tavern", "achievements", "level_up"])

func test_main_menu_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("main_menu")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Four kittens, infinite ways to die valiantly. Pick one.")
	assert_eq(steps[0].target_group, "tutorial_target_character_grid")
	assert_false(steps[0].touch_only)

func test_multiplayer_button_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("multiplayer_button")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Drag your friends into this mess with you.")
	assert_eq(steps[0].target_group, "tutorial_target_multiplayer_button")
	assert_false(steps[0].touch_only)

func test_shop_button_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("shop_button")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Spend your gold here. Retail therapy, but for wizards.")
	assert_eq(steps[0].target_group, "tutorial_target_shop_button")
	assert_false(steps[0].touch_only)

func test_movement_attack_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("movement_attack")
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text, "This stick makes you go places. Groundbreaking cat technology.")
	assert_eq(steps[0].target_group, "tutorial_target_joystick")
	assert_true(steps[0].touch_only)
	assert_eq(steps[1].text, "Mash this to hit things. It's 90% of your combat strategy, and also all of it.")
	assert_eq(steps[1].target_group, "tutorial_target_attack_button")
	assert_true(steps[1].touch_only)

func test_pause_menu_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("pause_menu")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Tap here to pause and manage your kitten — stats, skills, gear, items, achievements.")
	assert_eq(steps[0].target_group, "tutorial_target_pause_button")
	assert_false(steps[0].touch_only)

func test_stats_tab_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("stats_tab")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Stats tab — dump those points before you forget you have opposable thumbs.")
	assert_eq(steps[0].target_group, "tutorial_target_stats_tab")
	assert_false(steps[0].touch_only)

func test_skills_tab_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("skills_tab")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Skills tab — where the actual fun spells live, assuming you remember to equip them.")
	assert_eq(steps[0].target_group, "tutorial_target_skills_tab")
	assert_false(steps[0].touch_only)

func test_inventory_tab_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("inventory_tab")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Inventory tab — see everything you've picked up, ready to equip.")
	assert_eq(steps[0].target_group, "tutorial_target_inventory_tab")
	assert_false(steps[0].touch_only)

func test_items_tab_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("items_tab")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Items tab — use potions here to heal, restore mana, or shield yourself.")
	assert_eq(steps[0].target_group, "tutorial_target_items_tab")
	assert_false(steps[0].touch_only)

func test_achievements_tab_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("achievements_tab")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Achievements tab — see your progress and claim rewards you've earned.")
	assert_eq(steps[0].target_group, "tutorial_target_achievements_tab")
	assert_false(steps[0].touch_only)

func test_equip_gear_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("equip_gear")
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text, "Your equipped gear lives here. Tap a slot to inspect or unequip it.")
	assert_eq(steps[0].target_group, "tutorial_target_equip_slot")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Hit Equip on an item down here to gear up. Fashion optional, stats mandatory.")
	assert_eq(steps[1].target_group, "tutorial_target_bag_item")
	assert_false(steps[1].touch_only)

func test_assign_skills_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("assign_skills")
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text, "An unlocked skill — assign it to a hotbar slot to actually use it.")
	assert_eq(steps[0].target_group, "tutorial_target_skill_node")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Tap a number to bind it to that hotbar slot. Tap again to unbind.")
	assert_eq(steps[1].target_group, "tutorial_target_assign_slot")
	assert_false(steps[1].touch_only)

func test_tavern_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("tavern")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Walk up and hit attack to talk. Use up/down to navigate the menu, attack to confirm: Shop, buffs, or hire a Hooman.")
	assert_eq(steps[0].target_group, "tutorial_target_bartender")
	assert_false(steps[0].touch_only)

func test_achievements_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("achievements")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "That glow means you've earned an achievement. Go to the pause menu's Achievements tab to claim it.")
	assert_eq(steps[0].target_group, "tutorial_target_achievement_badge")
	assert_false(steps[0].touch_only)

func test_level_up_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("level_up")
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].text, "Level up! Check the pause menu — that's where those new stat points go.")
	assert_eq(steps[0].target_group, "tutorial_target_pause_button")
	assert_false(steps[0].touch_only)
	assert_true(steps[0].forced)

func test_unknown_topic_returns_empty_array():
	assert_eq(TutorialCatalog.steps_for("nonsense"), [])

func test_movement_attack_steps_are_touch_only():
	for step in TutorialCatalog.steps_for("movement_attack"):
		assert_true(step.touch_only)

func test_no_topic_has_empty_step_text():
	for topic_id in TutorialCatalog.topic_ids():
		for step in TutorialCatalog.steps_for(topic_id):
			assert_ne(step.text.strip_edges(), "")
