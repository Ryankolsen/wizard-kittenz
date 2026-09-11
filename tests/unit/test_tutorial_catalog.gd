extends GutTest

# Static tutorial content catalog (PRD #596, issue #597). Pure-data tests --
# no scene tree, no nodes. Mirrors test_achievement_catalog's shape of
# asserting exact text/target_group/touch_only per entry.

func test_topic_ids_returns_all_seven_in_order():
	assert_eq(TutorialCatalog.topic_ids(), ["main_menu", "movement_attack", "pause_menu", "equip_gear", "assign_skills", "tavern", "achievements"])

func test_main_menu_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("main_menu")
	assert_eq(steps.size(), 3)
	assert_eq(steps[0].text, "Four kittens, infinite ways to die valiantly. Pick one.")
	assert_eq(steps[0].target_group, "tutorial_target_character_grid")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Drag your friends into this mess with you — misery loves company, and so does loot-splitting.")
	assert_eq(steps[1].target_group, "tutorial_target_multiplayer_button")
	assert_false(steps[1].touch_only)
	assert_eq(steps[2].text, "Spend your gold here. Retail therapy, but for wizards.")
	assert_eq(steps[2].target_group, "tutorial_target_shop_button")
	assert_false(steps[2].touch_only)

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
	assert_eq(steps.size(), 6)
	assert_eq(steps[0].text, "Tap here to pause and manage your kitten — stats, skills, gear, items, achievements.")
	assert_eq(steps[0].target_group, "tutorial_target_pause_button")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Stats tab — dump those points before you forget you have opposable thumbs.")
	assert_eq(steps[1].target_group, "tutorial_target_stats_tab")
	assert_false(steps[1].touch_only)
	assert_eq(steps[2].text, "Skills tab — where the actual fun spells live, assuming you remember to equip them.")
	assert_eq(steps[2].target_group, "tutorial_target_skills_tab")
	assert_false(steps[2].touch_only)
	assert_eq(steps[3].text, "Inventory tab — see everything you've picked up, ready to equip.")
	assert_eq(steps[3].target_group, "tutorial_target_inventory_tab")
	assert_false(steps[3].touch_only)
	assert_eq(steps[4].text, "Items tab — potions, for when 'dodge better' stops being viable advice.")
	assert_eq(steps[4].target_group, "tutorial_target_items_tab")
	assert_false(steps[4].touch_only)
	assert_eq(steps[5].text, "Achievements tab — see your progress and claim rewards you've earned.")
	assert_eq(steps[5].target_group, "tutorial_target_achievements_tab")
	assert_false(steps[5].touch_only)

func test_equip_gear_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("equip_gear")
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text, "Click a slot, then click an item. Groundbreaking UX, we know.")
	assert_eq(steps[0].target_group, "tutorial_target_equip_slot")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Tap loot here to shove it onto your kitten. Fashion optional, stats mandatory.")
	assert_eq(steps[1].target_group, "tutorial_target_bag_item")
	assert_false(steps[1].touch_only)

func test_assign_skills_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("assign_skills")
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text, "An unlocked spell, just sitting there. Great personality, no stage time.")
	assert_eq(steps[0].target_group, "tutorial_target_skill_node")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Tap a number to bind it to that hotbar slot. Tap again to unbind.")
	assert_eq(steps[1].target_group, "tutorial_target_assign_slot")
	assert_false(steps[1].touch_only)

func test_tavern_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("tavern")
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text, "Walk up and hit attack to chat. He won't fight back — he's just thirsty. For gold, mostly.")
	assert_eq(steps[0].target_group, "tutorial_target_bartender")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Talk to him again for the menu: Shop, a beer (buffs your damage), or renting a Hooman to eat hits for you.")
	assert_eq(steps[1].target_group, "")
	assert_false(steps[1].touch_only)

func test_achievements_steps_have_correct_text_and_targets():
	var steps := TutorialCatalog.steps_for("achievements")
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].text, "That glow means you did something right, for once. Go claim your reward before you forget it exists.")
	assert_eq(steps[0].target_group, "tutorial_target_achievement_badge")
	assert_false(steps[0].touch_only)
	assert_eq(steps[1].text, "Click here to actually collect it. We don't do surprise deliveries.")
	assert_eq(steps[1].target_group, "")
	assert_false(steps[1].touch_only)

func test_unknown_topic_returns_empty_array():
	assert_eq(TutorialCatalog.steps_for("nonsense"), [])

func test_movement_attack_steps_are_touch_only():
	for step in TutorialCatalog.steps_for("movement_attack"):
		assert_true(step.touch_only)

func test_no_topic_has_empty_step_text():
	for topic_id in TutorialCatalog.topic_ids():
		for step in TutorialCatalog.steps_for(topic_id):
			assert_ne(step.text.strip_edges(), "")
