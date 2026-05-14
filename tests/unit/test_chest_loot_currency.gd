extends GutTest

# Tests for PRD #53 / issue #66 — chest loot credits CurrencyLedger.
# Standard chests pay Gold; rare chests pay Gems. Either way, the
# chest is single-use — a second open() is a no-op.

func test_standard_chest_open_credits_gold():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.STANDARD)
	var ok := chest.open(ledger)
	assert_true(ok)
	assert_true(ledger.balance(CurrencyLedger.Currency.GOLD) > 0)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD)

func test_standard_chest_does_not_credit_gems():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.STANDARD)
	chest.open(ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), 0)

func test_rare_chest_open_credits_gems():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.RARE)
	var ok := chest.open(ledger)
	assert_true(ok)
	assert_true(ledger.balance(CurrencyLedger.Currency.GEM) > 0)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), Chest.RARE_GEMS)

func test_rare_chest_does_not_credit_gold():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.RARE)
	chest.open(ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0)

func test_double_open_is_a_noop_standard():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.STANDARD)
	chest.open(ledger)
	var balance_after_first := ledger.balance(CurrencyLedger.Currency.GOLD)
	var ok2 := chest.open(ledger)
	assert_false(ok2)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), balance_after_first)

func test_double_open_is_a_noop_rare():
	var ledger := CurrencyLedger.new()
	var chest := Chest.make(Chest.Kind.RARE)
	chest.open(ledger)
	var balance_after_first := ledger.balance(CurrencyLedger.Currency.GEM)
	var ok2 := chest.open(ledger)
	assert_false(ok2)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GEM), balance_after_first)

func test_open_sets_is_opened():
	var chest := Chest.make(Chest.Kind.STANDARD)
	assert_false(chest.is_opened())
	chest.open(CurrencyLedger.new())
	assert_true(chest.is_opened())

func test_open_with_null_ledger_does_not_consume_chest():
	var chest := Chest.make(Chest.Kind.STANDARD)
	var ok := chest.open(null)
	assert_false(ok)
	assert_false(chest.is_opened())
	# Should still be openable afterwards with a real ledger.
	var ledger := CurrencyLedger.new()
	assert_true(chest.open(ledger))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD)

func test_amounts_are_constants_not_magic():
	# Pin the constants so a future tuning pass touches one place.
	assert_eq(Chest.STANDARD_GOLD, 25)
	assert_eq(Chest.RARE_GEMS, 5)

# --- Item drop seam (PRD #73 / issue #79) -----------------------------------

func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng

func test_open_without_rng_does_not_crash():
	# Backwards-compat: legacy callers pass only the ledger. open() must
	# tolerate the missing rng (uses a fresh one internally via the
	# resolver). last_item_drop may end up either null or non-null;
	# both are valid for an unseeded roll.
	var chest := Chest.make(Chest.Kind.STANDARD)
	var ok := chest.open(CurrencyLedger.new())
	assert_true(ok)

func test_standard_chest_item_drop_rate_around_twenty_five_percent():
	# Across 200 seeded opens, expect ~25% non-null item drops.
	var rng := _seeded_rng(11)
	var drops := 0
	for i in 200:
		var chest := Chest.make(Chest.Kind.STANDARD)
		chest.open(CurrencyLedger.new(), 11, rng)
		if chest.last_item_drop != null:
			drops += 1
	# 25% expected, wide tolerance for RNG variance.
	assert_true(drops > 30, "expected >15%% drops, got %d / 200" % drops)
	assert_true(drops < 80, "expected <40%% drops, got %d / 200" % drops)

func test_rare_chest_item_drop_rate_higher_than_standard():
	# RARE chests drop items more often than STANDARD ones (50% vs 25%).
	# Compare counts across matched batches.
	var rng_std := _seeded_rng(22)
	var rng_rare := _seeded_rng(22)
	var std_drops := 0
	var rare_drops := 0
	for i in 200:
		var std_chest := Chest.make(Chest.Kind.STANDARD)
		std_chest.open(CurrencyLedger.new(), 11, rng_std)
		if std_chest.last_item_drop != null:
			std_drops += 1
		var rare_chest := Chest.make(Chest.Kind.RARE)
		rare_chest.open(CurrencyLedger.new(), 11, rng_rare)
		if rare_chest.last_item_drop != null:
			rare_drops += 1
	assert_true(rare_drops > std_drops,
		"rare chests must drop more often than standard (rare=%d, std=%d)" % [rare_drops, std_drops])

func test_open_with_item_drop_returns_item_data():
	# Pin the field-access contract: after a successful open(), callers
	# read chest.last_item_drop. Find a seed that produces a hit so the
	# assertion is deterministic.
	var chest := Chest.make(Chest.Kind.RARE)
	# RARE has 50% drop chance — first seed that produces a non-null
	# drop suffices to pin the contract.
	var found := false
	for s in range(1, 50):
		var c := Chest.make(Chest.Kind.RARE)
		c.open(CurrencyLedger.new(), 11, _seeded_rng(s))
		if c.last_item_drop != null:
			assert_true(c.last_item_drop is ItemData,
				"last_item_drop typed as ItemData")
			found = true
			break
	assert_true(found, "found at least one seed producing a rare drop")

func test_open_failure_does_not_set_item_drop():
	# A null-ledger open() must not roll an item — it returns false
	# without touching last_item_drop.
	var chest := Chest.make(Chest.Kind.STANDARD)
	chest.open(null, 11, _seeded_rng(1))
	assert_null(chest.last_item_drop, "no item rolled on null-ledger failure")

func test_double_open_does_not_re_roll_item():
	# The idempotence guard covers items too — the second open() returns
	# false without mutating last_item_drop.
	var chest := Chest.make(Chest.Kind.STANDARD)
	chest.open(CurrencyLedger.new(), 11, _seeded_rng(1))
	var first_drop := chest.last_item_drop
	chest.open(CurrencyLedger.new(), 11, _seeded_rng(999))
	assert_eq(chest.last_item_drop, first_drop,
		"second open did not overwrite last_item_drop")
