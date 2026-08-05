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
	out.append(_tiered_gold("basic_tune_up", "self_heal_total", 100,
		"Basic Tune-Up",
		"100 HP self-healed. You patched yourself up like a real professional.",
		25))
	out.append(_tiered_potion("field_medic", "self_heal_total", 1000,
		"Field Medic",
		"1,000 HP self-healed. You could run your own clinic at this point.",
		"health_potion", 2))
	out.append(_tiered_item("immortal_ish", "self_heal_total", 10000,
		"Immortal-ish",
		"10,000 HP self-healed. Death has your number on speed dial and still can't reach you.",
		"guardians_locket"))
	out.append(_tiered_gold("warming_up", "damage_dealt", 1000,
		"Warming Up",
		"1,000 total damage dealt. The mice are starting to take notes.",
		25))
	out.append(_tiered_potion("certified_wrecking_ball", "damage_dealt", 10000,
		"Certified Wrecking Ball",
		"10,000 total damage dealt. Subtlety was never really your thing.",
		"health_potion", 2))
	out.append(_tiered_item("one_cat_apocalypse", "damage_dealt", 100000,
		"One-Cat Apocalypse",
		"100,000 total damage dealt. The dungeon files a formal ceasefire request.",
		"executioners_signet"))
	out.append(_tiered_gold("frequent_flyer", "dungeons_entered", 10,
		"Frequent Flyer",
		"Entered 10 dungeons. You know the drill by now.",
		25))
	out.append(_tiered_potion("dungeon_regular", "dungeons_entered", 50,
		"Dungeon Regular",
		"Entered 50 dungeons. The monsters know you by name. It's not a compliment.",
		"health_potion", 2))
	out.append(_tiered_item("dungeon_landlord", "dungeons_entered", 200,
		"Dungeon Landlord",
		"Entered 200 dungeons. At this point you should be collecting rent.",
		"bramble_plate"))
	out.append(_tiered_gold("curious_cat", "chests_opened", 10,
		"Curious Cat",
		"Opened 10 chests. Curiosity hasn't killed this cat yet.",
		25))
	out.append(_tiered_potion("chest_goblin", "chests_opened", 100,
		"Chest Goblin",
		"Opened 100 chests. You've developed a healthy respect for hinges.",
		"health_potion", 2))
	out.append(_tiered_item("hoarder_in_training", "chests_opened", 500,
		"Hoarder-in-Training",
		"Opened 500 chests. Your hoard rivals a dragon's, minus the dragon part.",
		"chest_goblin_gloves"))
	out.append(_tiered_gold("spare_change", "gold_earned", 100,
		"Spare Change",
		"Earned 100 lifetime gold. Every fortune starts with a few loose coins.",
		25))
	out.append(_tiered_potion("comfortably_well_off", "gold_earned", 1000,
		"Comfortably Well-Off",
		"Earned 1,000 lifetime gold. You've upgraded from ramen to premium kibble.",
		"health_potion", 2))
	out.append(_tiered_item("fat_cat", "gold_earned", 10000,
		"Fat Cat",
		"Earned 10,000 lifetime gold. You are, canonically, the fat cat now.",
		"fat_cat_coin_purse"))
	out.append(_tiered_gold("well_that_happened", "deaths", 1,
		"Well, That Happened",
		"You died. It happens to the best of us. Mostly to you, though.",
		25))
	out.append(_tiered_potion("frequent_flier_respawn_edition", "deaths", 10,
		"Frequent Flier (Respawn Edition)",
		"Died 10 times. You've got the respawn screen memorized by now.",
		"health_potion", 2))
	out.append(_tiered_item("professional_corpse", "deaths", 100,
		"Professional Corpse",
		"Died 100 times. At this point it's less a death count and more a resume.",
		"nine_lives_collar"))
	out.append(_tiered_gold("just_in_case", "potions_consumed", 10,
		"Just in Case",
		"Consumed 10 potions. You never know when you'll need a backup plan.",
		25))
	out.append(_tiered_potion("bottoms_up", "potions_consumed", 50,
		"Bottoms Up",
		"Consumed 50 potions. Your belt is basically a tiny pharmacy at this point.",
		"health_potion", 2))
	out.append(_tiered_item("potion_sommelier", "potions_consumed", 200,
		"Potion Sommelier",
		"Consumed 200 potions. You could rate the finish on a mana potion by now.",
		"alchemists_flask"))
	return out

# Tiered TOME entries (issue #460) share AchievementDefinition.make_tome's
# shape but bind to a counter_key/threshold instead of a trigger_event, same
# "empty trigger_event" pattern used for tiered GOLD/POTION entries elsewhere.
static func _tiered_tome(p_id: String, p_counter_key: String, p_threshold: int, p_title: String, p_flavor_text: String, p_node_id: String, p_spell_id: String) -> AchievementDefinition:
	var d := AchievementDefinition.make_tome(p_id, "", p_title, p_flavor_text, p_node_id, p_spell_id)
	d.counter_key = p_counter_key
	d.threshold = p_threshold
	return d

# Tiered GOLD/POTION/ITEM entries (issue #461) share the same "empty
# trigger_event + counter_key/threshold" shape as _tiered_tome above.
static func _tiered_gold(p_id: String, p_counter_key: String, p_threshold: int, p_title: String, p_flavor_text: String, p_gold_amount: int) -> AchievementDefinition:
	var d := AchievementDefinition.make_gold(p_id, "", p_title, p_flavor_text, p_gold_amount)
	d.counter_key = p_counter_key
	d.threshold = p_threshold
	return d

static func _tiered_potion(p_id: String, p_counter_key: String, p_threshold: int, p_title: String, p_flavor_text: String, p_potion_id: String, p_quantity: int) -> AchievementDefinition:
	var d := AchievementDefinition.make_potion(p_id, "", p_title, p_flavor_text, p_potion_id, p_quantity)
	d.counter_key = p_counter_key
	d.threshold = p_threshold
	return d

static func _tiered_item(p_id: String, p_counter_key: String, p_threshold: int, p_title: String, p_flavor_text: String, p_item_id: String) -> AchievementDefinition:
	var d := AchievementDefinition.make_item(p_id, "", p_title, p_flavor_text, p_item_id)
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
