extends GutTest

# Earnable Gem sources (PRD #53 / issue #67). Two play-milestone rewards:
#   - ProgressionSystem.add_xp credits LEVEL_UP_GEM_REWARD on each level gained.
#   - MetaProgressionTracker.record_first_clear credits a one-time
#     FIRST_DUNGEON_CLEAR_GEM_REWARD per dungeon id, with repeat calls a no-op.

func test_level_up_credits_gems():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var ledger := CurrencyLedger.new()
	var levels := ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1), ledger)
	assert_eq(levels, 1)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), ProgressionSystem.LEVEL_UP_GEM_REWARD)

func test_level_up_does_not_credit_gold():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var ledger := CurrencyLedger.new()
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1), ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)

func test_multi_level_chain_credits_per_level():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var ledger := CurrencyLedger.new()
	var total := ProgressionSystem.xp_to_next_level(1) \
		+ ProgressionSystem.xp_to_next_level(2) \
		+ ProgressionSystem.xp_to_next_level(3)
	var levels := ProgressionSystem.add_xp(c, total, ledger)
	assert_eq(levels, 3)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), ProgressionSystem.LEVEL_UP_GEM_REWARD * 3)

func test_null_ledger_is_safe():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var levels := ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1))
	assert_eq(levels, 1, "legacy 2-arg call still works without a ledger")

func test_no_level_up_no_gems():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var ledger := CurrencyLedger.new()
	ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(1) - 1, ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0, "XP that does not trigger a level-up pays no Gems")

func test_first_dungeon_clear_credits_gems():
	var tracker := MetaProgressionTracker.new()
	var ledger := CurrencyLedger.new()
	var rewarded := tracker.record_first_clear("dungeon_1", ledger)
	assert_true(rewarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), MetaProgressionTracker.FIRST_DUNGEON_CLEAR_GEM_REWARD)
	assert_true(tracker.has_cleared("dungeon_1"))

func test_repeat_clear_is_noop():
	var tracker := MetaProgressionTracker.new()
	var ledger := CurrencyLedger.new()
	tracker.record_first_clear("dungeon_1", ledger)
	var second := tracker.record_first_clear("dungeon_1", ledger)
	assert_false(second)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), MetaProgressionTracker.FIRST_DUNGEON_CLEAR_GEM_REWARD,
		"repeat clear does not credit Gems a second time")

func test_distinct_dungeons_each_pay_once():
	var tracker := MetaProgressionTracker.new()
	var ledger := CurrencyLedger.new()
	tracker.record_first_clear("dungeon_1", ledger)
	tracker.record_first_clear("dungeon_2", ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), MetaProgressionTracker.FIRST_DUNGEON_CLEAR_GEM_REWARD * 2)

func test_record_first_clear_empty_id_rejected():
	var tracker := MetaProgressionTracker.new()
	var ledger := CurrencyLedger.new()
	var rewarded := tracker.record_first_clear("", ledger)
	assert_false(rewarded)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)
	assert_eq(tracker.cleared_dungeons.size(), 0)

func test_record_first_clear_null_ledger_still_marks():
	var tracker := MetaProgressionTracker.new()
	var rewarded := tracker.record_first_clear("dungeon_1", null)
	assert_true(rewarded)
	assert_true(tracker.has_cleared("dungeon_1"))
	assert_false(tracker.record_first_clear("dungeon_1", null), "still no-op on repeat even when ledger was null")

func test_cleared_dungeons_survives_save_round_trip():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var tracker := MetaProgressionTracker.new()
	var ledger := CurrencyLedger.new()
	tracker.record_first_clear("dungeon_1", ledger)
	tracker.record_first_clear("dungeon_2", ledger)
	var save := KittenSaveData.from_character(c, null, tracker)
	var dict := save.to_dict()
	var restored := KittenSaveData.from_dict(dict)
	var restored_tracker := restored.to_tracker()
	assert_true(restored_tracker.has_cleared("dungeon_1"))
	assert_true(restored_tracker.has_cleared("dungeon_2"))
	# Repeat clear after reload remains a no-op.
	var ledger2 := CurrencyLedger.new()
	var rewarded := restored_tracker.record_first_clear("dungeon_1", ledger2)
	assert_false(rewarded)
	assert_eq(ledger2.balance(CurrencyLedger.Currency.GEM), 0)

func test_legacy_save_defaults_to_empty_cleared_dungeons():
	var restored := KittenSaveData.from_dict({})
	assert_eq(restored.cleared_dungeons.size(), 0)
	var tracker := restored.to_tracker()
	assert_eq(tracker.cleared_dungeons.size(), 0)
