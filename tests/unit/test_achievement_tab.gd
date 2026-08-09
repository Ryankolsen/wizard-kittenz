extends GutTest

# Issue #451 (PRD #446 slice 5). The Achievements tab lists unlocked entries
# from AchievementService.account.achievement_state and routes claim taps
# through AchievementService.claim() (#448). Only the pure row-shaping helpers
# on the pause menu script are unit-tested here — the full panel render is a
# scene-tree UI concern verified manually in the QA pass (#452), per the
# issue note.

const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")

func _catalog() -> Array:
	return [
		AchievementDefinition.make_gold("a_gold", "evt_a", "Gold One", "flavor a", 50),
		AchievementDefinition.make_potion("b_potion", "evt_b", "Potion One", "flavor b", "health_potion", 2),
	]

func test_achievement_rows_only_includes_entries_present_in_state():
	var state := {
		"a_gold": {"unlocked_at": 1, "claimed": false, "earned_by_slot": "wizard"},
	}
	var rows := PauseMenuScript._achievement_rows(state, _catalog())
	assert_eq(rows.size(), 1, "locked/never-unlocked achievements are not listed")
	assert_eq(rows[0]["id"], "a_gold")
	assert_false(rows[0]["claimed"])

func test_achievement_rows_preserves_catalog_order():
	var state := {
		"b_potion": {"unlocked_at": 1, "claimed": false, "earned_by_slot": "wizard"},
		"a_gold": {"unlocked_at": 2, "claimed": true, "earned_by_slot": "wizard"},
	}
	var rows := PauseMenuScript._achievement_rows(state, _catalog())
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["id"], "a_gold", "rows follow catalog order, not insertion order")
	assert_eq(rows[1]["id"], "b_potion")
	assert_true(rows[0]["claimed"])
	assert_false(rows[1]["claimed"])

func test_achievement_rows_empty_state_returns_empty():
	assert_eq(PauseMenuScript._achievement_rows({}, _catalog()).size(), 0)

func test_achievement_reward_text_gold():
	var def := AchievementDefinition.make_gold("g", "evt", "T", "F", 50)
	assert_eq(PauseMenuScript._achievement_reward_text(def), "+50 Gold")

func test_achievement_reward_text_potion_uses_catalog_display_name():
	var def := AchievementDefinition.make_potion("p", "evt", "T", "F", "health_potion", 2)
	var expected := "+2 %s" % PotionCatalog.find("health_potion").display_name
	assert_eq(PauseMenuScript._achievement_reward_text(def), expected)

func test_achievement_reward_text_unknown_potion_falls_back_to_id():
	var def := AchievementDefinition.make_potion("p", "evt", "T", "F", "not_a_real_potion", 1)
	assert_eq(PauseMenuScript._achievement_reward_text(def), "+1 not_a_real_potion")

func test_achievement_reward_text_item_uses_catalog_display_name():
	var def := AchievementDefinition.make_item("i", "evt", "T", "F", "guardians_locket")
	var expected := ItemCatalog.find("guardians_locket").display_name
	assert_eq(PauseMenuScript._achievement_reward_text(def), expected)

func test_achievement_reward_text_unknown_item_falls_back_to_id():
	var def := AchievementDefinition.make_item("i", "evt", "T", "F", "not_a_real_item")
	assert_eq(PauseMenuScript._achievement_reward_text(def), "not_a_real_item")

func test_achievement_reward_text_tome_uses_node_display_name():
	var def := AchievementDefinition.make_tome("m", "", "T", "F", "phase_tome_i", "phase_tome_i")
	assert_eq(PauseMenuScript._achievement_reward_text(def), "Phase Tome I")

func test_achievement_reward_text_unknown_tome_falls_back_to_id():
	var def := AchievementDefinition.make_tome("m", "", "T", "F", "not_a_real_node", "not_a_real_spell")
	assert_eq(PauseMenuScript._achievement_reward_text(def), "not_a_real_node")

func test_achievement_reward_text_none_shows_memorial_badge():
	var def := AchievementDefinition.make_none("m", "", "T", "F")
	assert_eq(PauseMenuScript._achievement_reward_text(def), "Memorial Badge")
