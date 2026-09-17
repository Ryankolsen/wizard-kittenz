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
	"multiplayer_button",
	"shop_button",
	"movement_attack",
	"pause_menu",
	"stats_tab",
	"skills_tab",
	"inventory_tab",
	"items_tab",
	"achievements_tab",
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
		"multiplayer_button":
			return _multiplayer_button_steps()
		"shop_button":
			return _shop_button_steps()
		"movement_attack":
			return _movement_attack_steps()
		"pause_menu":
			return _pause_menu_steps()
		"stats_tab":
			return _stats_tab_steps()
		"skills_tab":
			return _skills_tab_steps()
		"inventory_tab":
			return _inventory_tab_steps()
		"items_tab":
			return _items_tab_steps()
		"achievements_tab":
			return _achievements_tab_steps()
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

static func _step(p_text: String, p_target_group: String, p_touch_only: bool, p_forced: bool = false) -> Dictionary:
	return {
		"text": p_text,
		"target_group": p_target_group,
		"touch_only": p_touch_only,
		"forced": p_forced,
	}

static func _main_menu_steps() -> Array[Dictionary]:
	return [
		_step("Four kittens, infinite ways to die valiantly. Pick one.",
			"tutorial_target_character_grid", false),
	]

static func _multiplayer_button_steps() -> Array[Dictionary]:
	return [
		_step("Drag your friends into this mess with you.",
			"tutorial_target_multiplayer_button", false),
	]

static func _shop_button_steps() -> Array[Dictionary]:
	return [
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
	]

static func _stats_tab_steps() -> Array[Dictionary]:
	return [
		_step("Stats tab — dump those points before you forget you have opposable thumbs.",
			"tutorial_target_stats_tab", false),
	]

static func _skills_tab_steps() -> Array[Dictionary]:
	return [
		_step("Skills tab — where the actual fun spells live, assuming you remember to equip them.",
			"tutorial_target_skills_tab", false),
	]

static func _inventory_tab_steps() -> Array[Dictionary]:
	return [
		_step("Inventory tab — see everything you've picked up, ready to equip.",
			"tutorial_target_inventory_tab", false),
	]

static func _items_tab_steps() -> Array[Dictionary]:
	return [
		_step("Items tab — use potions here to heal, restore mana, or shield yourself.",
			"tutorial_target_items_tab", false),
	]

static func _achievements_tab_steps() -> Array[Dictionary]:
	return [
		_step("Achievements tab — see your progress and claim rewards you've earned.",
			"tutorial_target_achievements_tab", false),
	]

static func _equip_gear_steps() -> Array[Dictionary]:
	return [
		_step("Your equipped gear lives here. Tap a slot to inspect or unequip it.",
			"tutorial_target_equip_slot", false),
		_step("Hit Equip on an item down here to gear up. Fashion optional, stats mandatory.",
			"tutorial_target_bag_item", false),
	]

static func _assign_skills_steps() -> Array[Dictionary]:
	return [
		_step("An unlocked skill — assign it to a hotbar slot to actually use it.",
			"tutorial_target_skill_node", false),
		_step("Tap a number to bind it to that hotbar slot. Tap again to unbind.",
			"tutorial_target_assign_slot", false),
	]

static func _tavern_steps() -> Array[Dictionary]:
	return [
		_step("Walk up and hit attack to talk. Use up/down to navigate the menu, attack to confirm: Shop, buffs, or hire a Hooman.",
			"tutorial_target_bartender", false),
	]

static func _achievements_steps() -> Array[Dictionary]:
	return [
		_step("That glow means you've earned an achievement. Go to the pause menu's Achievements tab to claim it.",
			"tutorial_target_achievement_badge", false),
	]
