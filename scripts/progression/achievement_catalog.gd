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
	return out

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
