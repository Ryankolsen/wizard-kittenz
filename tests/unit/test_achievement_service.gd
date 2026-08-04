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
