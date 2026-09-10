extends GutTest

# Issue #599 (PRD #596) — tutorial_seen_topics account-wide persistence.
# Pins the round-trip through AccountSaveData and GameState hydration/clear,
# following the same plumbing already proven for streak_day/cleared_dungeons.

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func test_account_save_data_round_trips_tutorial_seen_topics():
	var account := AccountSaveData.from_state(null, null, null, null, null, 0, "", {}, ["pause_menu"])
	assert_eq(account.tutorial_seen_topics, ["pause_menu"])
	var restored := AccountSaveData.from_dict(account.to_dict())
	assert_eq(restored.tutorial_seen_topics, ["pause_menu"],
		"tutorial_seen_topics must round-trip through to_dict/from_dict unchanged")

func test_from_dict_defaults_missing_field_to_empty_array():
	var account := AccountSaveData.from_dict({})
	assert_eq(account.tutorial_seen_topics, [],
		"an old save with no tutorial_seen_topics key must default to an empty array")

func test_game_state_hydrate_populates_tutorial_seen_topics():
	var bundle := SaveBundle.new()
	bundle.account.tutorial_seen_topics = ["tavern"]
	var gs := get_node("/root/GameState")
	gs.hydrate_from_bundle(bundle)
	assert_eq(gs.tutorial_seen_topics, ["tavern"],
		"hydrate_from_bundle must populate GameState.tutorial_seen_topics from the loaded account")

func test_game_state_clear_resets_tutorial_seen_topics():
	var gs := get_node("/root/GameState")
	gs.tutorial_seen_topics = ["main_menu"]
	gs.clear()
	assert_eq(gs.tutorial_seen_topics, [],
		"clear() must reset tutorial_seen_topics to an empty array")
