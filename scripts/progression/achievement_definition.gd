class_name AchievementDefinition
extends RefCounted

# Pure data (PRD #446 / issue #447). One entry describes a single achievement:
# the event key that unlocks it, its display copy, and its fixed reward.
# Rewards are never randomized — a flat gold amount, a potion id + quantity,
# or an item catalog id, routed by AchievementService.claim() (issue #448,
# item routing added in #458).

enum RewardType { GOLD, POTION, ITEM }

var id: String = ""
var trigger_event: String = ""
# Tiered achievements (issue #455): counter_key/threshold coexist with
# trigger_event and are used by AchievementService.increment_counter instead
# of record_event. Empty counter_key means "not a tiered achievement".
var counter_key: String = ""
var threshold: int = 0
var title: String = ""
var flavor_text: String = ""
var reward_type: int = RewardType.GOLD
var reward_potion_id: String = ""
var reward_amount: int = 0
var reward_item_id: String = ""

static func make_gold(p_id: String, p_trigger_event: String, p_title: String, p_flavor_text: String, p_gold_amount: int) -> AchievementDefinition:
	var d := AchievementDefinition.new()
	d.id = p_id
	d.trigger_event = p_trigger_event
	d.title = p_title
	d.flavor_text = p_flavor_text
	d.reward_type = RewardType.GOLD
	d.reward_amount = p_gold_amount
	return d

static func make_potion(p_id: String, p_trigger_event: String, p_title: String, p_flavor_text: String, p_potion_id: String, p_quantity: int = 1) -> AchievementDefinition:
	var d := AchievementDefinition.new()
	d.id = p_id
	d.trigger_event = p_trigger_event
	d.title = p_title
	d.flavor_text = p_flavor_text
	d.reward_type = RewardType.POTION
	d.reward_potion_id = p_potion_id
	d.reward_amount = p_quantity
	return d

static func make_item(p_id: String, p_trigger_event: String, p_title: String, p_flavor_text: String, p_item_id: String) -> AchievementDefinition:
	var d := AchievementDefinition.new()
	d.id = p_id
	d.trigger_event = p_trigger_event
	d.title = p_title
	d.flavor_text = p_flavor_text
	d.reward_type = RewardType.ITEM
	d.reward_item_id = p_item_id
	return d
