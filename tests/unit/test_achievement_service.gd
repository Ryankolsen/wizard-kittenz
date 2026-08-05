extends GutTest

# Engine core for achievements (PRD #446 / issue #447). AchievementService is
# the deep module under test: record_event(event_key) unlocks any catalog
# definitions bound to that key, exactly once, into AccountSaveData's
# account-wide achievement_state. Uses a small in-test catalog (not the real
# AchievementCatalog) so content changes can't break this spec.

func _make_definition(id: String, trigger_event: String) -> AchievementDefinition:
	return AchievementDefinition.make_gold(id, trigger_event, "Title", "Flavor text.", 10)

func _make_tiered_definition(id: String, counter_key: String, threshold: int) -> AchievementDefinition:
	var d := AchievementDefinition.make_gold(id, "", "Title", "Flavor text.", 10)
	d.counter_key = counter_key
	d.threshold = threshold
	return d

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

# --- claim() (issue #448) -----------------------------------------------------

func _make_potion_definition(id: String, trigger_event: String, potion_id: String, quantity: int = 1) -> AchievementDefinition:
	return AchievementDefinition.make_potion(id, trigger_event, "Title", "Flavor text.", potion_id, quantity)

func test_claim_gold_credits_account_balance():
	var def := _make_definition("gold_ach", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.record_event("test_event")
	var ledger := CurrencyLedger.new()
	var claimed := service.claim("gold_ach", ledger, null, null)
	assert_not_null(claimed)
	assert_eq(claimed.id, "gold_ach")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), def.reward_amount)
	assert_true(account.achievement_state["gold_ach"]["claimed"])

func test_claim_potion_active_slot_credits_live_inventory():
	var def := _make_potion_definition("potion_ach", "test_event", "health_potion", 2)
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard"
	service.record_event("test_event")
	var inv := ConsumableInventory.new()
	var claimed := service.claim("potion_ach", null, inv, null)
	assert_not_null(claimed)
	assert_eq(inv.count_of("health_potion"), 2)

func test_claim_potion_inactive_slot_mutates_bundle_slot_only():
	var def := _make_potion_definition("potion_ach", "test_event", "health_potion", 2)
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard"
	service.record_event("test_event")
	# Earn while active on "wizard", then switch active_slot before claiming —
	# reward must land on the earning slot ("wizard"), not the now-active one.
	service.active_slot = "battle"
	var bundle := SaveBundle.new()
	var wizard_slot := CharacterSlotData.new()
	bundle.slots[SaveBundle.SLOT_WIZARD] = wizard_slot
	var active_inv := ConsumableInventory.new()
	var claimed := service.claim("potion_ach", null, active_inv, bundle)
	assert_not_null(claimed)
	assert_eq(wizard_slot.consumable_inventory_data.get("health_potion", 0), 2)
	assert_eq(active_inv.count_of("health_potion"), 0,
		"the currently-active slot's live inventory must not be touched")

func test_claim_returns_definition_for_ui():
	var def := _make_definition("gold_ach", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.record_event("test_event")
	var claimed := service.claim("gold_ach", CurrencyLedger.new(), null, null)
	assert_same(claimed, def)

func test_claim_twice_only_grants_reward_once():
	var def := _make_definition("gold_ach", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.record_event("test_event")
	var ledger := CurrencyLedger.new()
	service.claim("gold_ach", ledger, null, null)
	var second := service.claim("gold_ach", ledger, null, null)
	assert_null(second, "second claim on an already-claimed id is a no-op")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), def.reward_amount,
		"balance only increased once")
	assert_true(account.achievement_state["gold_ach"]["claimed"])

func _make_item_definition(id: String, trigger_event: String, item_id: String) -> AchievementDefinition:
	return AchievementDefinition.make_item(id, trigger_event, "Title", "Flavor text.", item_id)

func test_claim_item_active_slot_adds_to_live_bag():
	var def := _make_item_definition("item_ach", "test_event", "lucky_charm")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard"
	service.record_event("test_event")
	var inv := ItemInventory.new()
	var claimed := service.claim("item_ach", null, null, null, inv)
	assert_not_null(claimed)
	assert_eq(inv.bag_items().size(), 1)
	assert_eq(inv.bag_items()[0].id, "lucky_charm")

func test_claim_item_inactive_slot_mutates_bundle_slot_only():
	var def := _make_item_definition("item_ach", "test_event", "lucky_charm")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard"
	service.record_event("test_event")
	service.active_slot = "battle"
	var bundle := SaveBundle.new()
	var wizard_slot := CharacterSlotData.new()
	bundle.slots[SaveBundle.SLOT_WIZARD] = wizard_slot
	var active_inv := ItemInventory.new()
	var claimed := service.claim("item_ach", null, null, bundle, active_inv)
	assert_not_null(claimed)
	assert_true(wizard_slot.item_bag.has("lucky_charm"))
	assert_eq(active_inv.bag_items().size(), 0,
		"the currently-active slot's live inventory must not be touched")

func test_claim_item_twice_does_not_duplicate_in_bag():
	var def := _make_item_definition("item_ach", "test_event", "lucky_charm")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard"
	service.record_event("test_event")
	var inv := ItemInventory.new()
	service.claim("item_ach", null, null, null, inv)
	var second := service.claim("item_ach", null, null, null, inv)
	assert_null(second, "second claim on an already-claimed id is a no-op")
	assert_eq(inv.bag_items().size(), 1, "item is not duplicated in the bag")

func test_claim_nonexistent_id_is_safe_no_op():
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [])
	var ledger := CurrencyLedger.new()
	var claimed := service.claim("nonexistent_id", ledger, null, null)
	assert_null(claimed)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)

func test_claim_never_unlocked_is_safe_no_op():
	var def := _make_definition("gold_ach", "test_event")
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	# Note: record_event was never called, so achievement_state has no entry.
	var ledger := CurrencyLedger.new()
	var claimed := service.claim("gold_ach", ledger, null, null)
	assert_null(claimed)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)

# --- increment_counter (tiered achievements, issue #455) -----------------------

func test_increment_counter_below_threshold_does_not_unlock():
	var def := _make_tiered_definition("tier_ach", "test_counter", 10)
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.increment_counter("test_counter", 5)
	assert_false(account.achievement_state.has("tier_ach"))

func test_increment_counter_crossing_threshold_unlocks_once():
	var def := _make_tiered_definition("tier_ach", "test_counter", 10)
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard_kitten"
	watch_signals(service)
	service.increment_counter("test_counter", 5)
	service.increment_counter("test_counter", 5)
	assert_true(account.achievement_state.has("tier_ach"))
	var entry: Dictionary = account.achievement_state["tier_ach"]
	assert_false(entry["claimed"])
	assert_eq(entry["earned_by_slot"], "wizard_kitten")
	assert_signal_emit_count(service, "achievement_unlocked", 1)

func test_increment_counter_past_threshold_is_idempotent():
	var def := _make_tiered_definition("tier_ach", "test_counter", 10)
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.increment_counter("test_counter", 10)
	watch_signals(service)
	var entry_before: Dictionary = account.achievement_state["tier_ach"].duplicate()
	service.increment_counter("test_counter", 100)
	assert_signal_not_emitted(service, "achievement_unlocked")
	assert_eq(account.achievement_state["tier_ach"], entry_before)

func test_achievement_counters_round_trip_through_dict():
	var def := _make_tiered_definition("tier_ach", "test_counter", 10)
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.increment_counter("test_counter", 4)
	var loaded := AccountSaveData.from_dict(account.to_dict())
	assert_eq(loaded.achievement_counters["test_counter"], 4)

func test_increment_counter_is_shared_across_slots():
	var def := _make_tiered_definition("tier_ach", "test_counter", 10)
	var account := AccountSaveData.new()
	var service := AchievementService.new(account, [def])
	service.active_slot = "wizard_kitten"
	service.increment_counter("test_counter", 4)
	service.active_slot = "chonk_kitten"
	service.increment_counter("test_counter", 4)
	assert_eq(account.achievement_counters["test_counter"], 8)
	assert_false(account.achievement_state.has("tier_ach"))
