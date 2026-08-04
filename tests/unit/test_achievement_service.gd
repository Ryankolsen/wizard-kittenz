extends GutTest

# Engine core for achievements (PRD #446 / issue #447). AchievementService is
# the deep module under test: record_event(event_key) unlocks any catalog
# definitions bound to that key, exactly once, into AccountSaveData's
# account-wide achievement_state. Uses a small in-test catalog (not the real
# AchievementCatalog) so content changes can't break this spec.

func _make_definition(id: String, trigger_event: String) -> AchievementDefinition:
	return AchievementDefinition.make_gold(id, trigger_event, "Title", "Flavor text.", 10)

# --- Core wiring -------------------------------------------------------------

func test_record_event_unlocks_matching_definition():
	var def := _make_definition("def_a", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.record_event("test_event")
	assert_true(account.achievement_state.has(def.id))
	assert_false(account.achievement_state[def.id]["claimed"])

# --- Content details ----------------------------------------------------------

func test_record_event_captures_active_slot_and_timestamp():
	var def := _make_definition("def_a", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard_kitten"
	service.record_event("test_event")
	var entry: Dictionary = account.achievement_state[def.id]
	assert_eq(entry["earned_by_slot"], "wizard_kitten")
	assert_true(float(entry["unlocked_at"]) > 0.0, "unlocked_at is a non-zero timestamp")

func test_signal_emitted_with_correct_id():
	var def := _make_definition("def_a", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	watch_signals(service)
	service.record_event("test_event")
	assert_signal_emitted_with_parameters(service, "achievement_unlocked", [def.id])

# --- Edge cases ----------------------------------------------------------------

func test_record_event_twice_unlocks_only_once():
	var def := _make_definition("def_a", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	watch_signals(service)
	service.record_event("test_event")
	service.record_event("test_event")
	assert_eq(account.achievement_state.size(), 1)
	assert_signal_emit_count(service, "achievement_unlocked", 1)

func test_unknown_event_is_safe_no_op():
	var def := _make_definition("def_a", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	watch_signals(service)
	service.record_event("unknown_event")
	assert_eq(account.achievement_state.size(), 0)
	assert_signal_not_emitted(service, "achievement_unlocked")

func test_two_definitions_same_event_both_unlock():
	var def_a := _make_definition("def_a", "test_event")
	var def_b := _make_definition("def_b", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def_a, def_b])
	service.record_event("test_event")
	assert_true(account.achievement_state.has("def_a"))
	assert_true(account.achievement_state.has("def_b"))

func test_repeat_call_does_not_overwrite_existing_entry():
	var def := _make_definition("def_a", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.record_event("test_event")
	var first_entry: Dictionary = account.achievement_state[def.id].duplicate()
	first_entry["claimed"] = true
	account.achievement_state[def.id] = first_entry
	service.record_event("test_event")
	assert_true(account.achievement_state[def.id]["claimed"],
		"second record_event must not reset an already-unlocked entry")

# --- Save round-trip -----------------------------------------------------------

func test_achievement_state_round_trips_through_dict():
	var def := _make_definition("def_a", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "chonk_kitten"
	service.record_event("test_event")
	var loaded := AccountSaveData.from_dict(account.to_dict())
	assert_true(loaded.achievement_state.has(def.id))
	assert_eq(loaded.achievement_state[def.id]["earned_by_slot"], "chonk_kitten")
	assert_false(loaded.achievement_state[def.id]["claimed"])
