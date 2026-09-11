class_name TutorialCatalog
extends RefCounted

# Static registry of every tutorial topic and its ordered steps (PRD #596 /
# issue #597). Pure data, mirroring AchievementCatalog -- content authoring
# never touches TutorialOverlay directly. Each step's target_group names a
# Godot group TutorialOverlay will search for at trigger time via
# get_tree().get_first_node_in_group(target_group); an empty target_group
# renders as a plain centered text bubble with no highlight box. The groups
# themselves don't exist in the scene tree yet -- later wiring slices add
# the matching add_to_group() calls.

const TOPIC_IDS: Array[String] = [
	"main_menu",
	"movement_attack",
	"pause_menu",
	"equip_gear",
	"assign_skills",
	"tavern",
	"achievements",
]

static func topic_ids() -> Array[String]:
	return TOPIC_IDS.duplicate()

static func steps_for(topic_id: String) -> Array[Dictionary]:
	match topic_id:
		"main_menu":
			return _main_menu_steps()
		"movement_attack":
			return _movement_attack_steps()
		"pause_menu":
			return _pause_menu_steps()
		"equip_gear":
			return _equip_gear_steps()
		"assign_skills":
			return _assign_skills_steps()
		"tavern":
			return _tavern_steps()
		"achievements":
			return _achievements_steps()
		_:
			return []

static func _step(p_text: String, p_target_group: String, p_touch_only: bool) -> Dictionary:
	return {
		"text": p_text,
		"target_group": p_target_group,
		"touch_only": p_touch_only,
	}

static func _main_menu_steps() -> Array[Dictionary]:
	return [
		_step("Four kittens, infinite ways to die valiantly. Pick one.",
			"tutorial_target_character_grid", false),
		_step("Drag your friends into this mess with you — misery loves company, and so does loot-splitting.",
			"tutorial_target_multiplayer_button", false),
		_step("Spend your gold here. Retail therapy, but for wizards.",
			"tutorial_target_shop_button", false),
	]

static func _movement_attack_steps() -> Array[Dictionary]:
	return [
		_step("This stick makes you go places. Groundbreaking cat technology.",
			"tutorial_target_joystick", true),
		_step("Mash this to hit things. It's 90% of your combat strategy, and also all of it.",
			"tutorial_target_attack_button", true),
	]

static func _pause_menu_steps() -> Array[Dictionary]:
	return [
		_step("Tap here to pause and manage your kitten — stats, skills, gear, items, achievements.",
			"tutorial_target_pause_button", false),
		_step("Stats tab — dump those points before you forget you have opposable thumbs.",
			"tutorial_target_stats_tab", false),
		_step("Skills tab — where the actual fun spells live, assuming you remember to equip them.",
			"tutorial_target_skills_tab", false),
		_step("Inventory tab — see everything you've picked up, ready to equip.",
			"tutorial_target_inventory_tab", false),
		_step("Items tab — potions, for when 'dodge better' stops being viable advice.",
			"tutorial_target_items_tab", false),
		_step("Achievements tab — see your progress and claim rewards you've earned.",
			"tutorial_target_achievements_tab", false),
	]

static func _equip_gear_steps() -> Array[Dictionary]:
	return [
		_step("Click a slot, then click an item. Groundbreaking UX, we know.",
			"tutorial_target_equip_slot", false),
		_step("Tap loot here to shove it onto your kitten. Fashion optional, stats mandatory.",
			"tutorial_target_bag_item", false),
	]

static func _assign_skills_steps() -> Array[Dictionary]:
	return [
		_step("An unlocked spell, just sitting there. Great personality, no stage time.",
			"tutorial_target_skill_node", false),
		_step("Tap a number to bind it to that hotbar slot. Tap again to unbind.",
			"tutorial_target_assign_slot", false),
	]

static func _tavern_steps() -> Array[Dictionary]:
	return [
		_step("Walk up and hit attack to chat. He won't fight back — he's just thirsty. For gold, mostly.",
			"tutorial_target_bartender", false),
		_step("Talk to him again for the menu: Shop, a beer (buffs your damage), or renting a Hooman to eat hits for you.",
			"", false),
	]

static func _achievements_steps() -> Array[Dictionary]:
	return [
		_step("That glow means you did something right, for once. Go claim your reward before you forget it exists.",
			"tutorial_target_achievement_badge", false),
		_step("Click here to actually collect it. We don't do surprise deliveries.",
			"", false),
	]
