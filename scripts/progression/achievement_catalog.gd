class_name AchievementCatalog
extends RefCounted

# Static registry of every achievement (PRD #446 / issue #447). Pure data,
# mirroring ItemCatalog/PotionCatalog — content authoring never touches
# AchievementService. The 4 entries here are the PRD's test set; their
# trigger_event keys are wired to gameplay call sites in issue #449.

static func all() -> Array:
	var out: Array = []
	out.append(AchievementDefinition.make_gold(
		"first_rename", "cat_renamed",
		"What's in a Name?",
		"You gave your kitten a name that isn't \"Kitten.\" Bold choice.",
		50))
	out.append(AchievementDefinition.make_gold(
		"first_dungeon", "dungeon_entered",
		"Into the Litterbox... I Mean Dungeon",
		"You walked into a dark, monster-filled hole voluntarily. Very cat of you.",
		75))
	out.append(AchievementDefinition.make_potion(
		"first_chest", "chest_opened",
		"Curiosity Fed the Cat",
		"You opened a chest. It did not, in fact, kill you.",
		"health_potion", 1))
	out.append(AchievementDefinition.make_potion(
		"first_kill", "enemy_killed",
		"First Blood (Mouse Blood)",
		"You defeated an enemy. Somewhere, a tiny mouse skeleton salutes you.",
		"mana_potion", 1))
	out.append(_tiered_tome("mouse_patrol", "enemies_killed", 10,
		"Mouse Patrol",
		"10 kills. The dungeon HR department has noticed.",
		"phase_tome_i", "phase_tome_i"))
	out.append(_tiered_tome("certified_menace", "enemies_killed", 100,
		"Certified Menace",
		"100 kills. You've stopped counting the guilt.",
		"phase_tome_ii", "phase_tome_ii"))
	out.append(_tiered_tome("apex_predator_probably", "enemies_killed", 1000,
		"Apex Predator (Probably)",
		"1,000 kills. Somewhere, a mouse union is filing a complaint.",
		"phase_tome_iii", "phase_tome_iii"))
	return out

# Tiered TOME entries (issue #460) share AchievementDefinition.make_tome's
# shape but bind to a counter_key/threshold instead of a trigger_event, same
# "empty trigger_event" pattern used for tiered GOLD/POTION entries elsewhere.
static func _tiered_tome(p_id: String, p_counter_key: String, p_threshold: int, p_title: String, p_flavor_text: String, p_node_id: String, p_spell_id: String) -> AchievementDefinition:
	var d := AchievementDefinition.make_tome(p_id, "", p_title, p_flavor_text, p_node_id, p_spell_id)
	d.counter_key = p_counter_key
	d.threshold = p_threshold
	return d

static func find(id: String) -> AchievementDefinition:
	for d in all():
		if d.id == id:
			return d
	return null

static func for_trigger(event_key: String) -> Array:
	var out: Array = []
	for d in all():
		if d.trigger_event == event_key:
			out.append(d)
	return out
