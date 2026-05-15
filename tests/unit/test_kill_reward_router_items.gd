extends GutTest

# Tests for the item drop seam wired into KillRewardRouter (PRD #73 /
# issue #79). The router returns an ItemData (or null) so Player.gd
# can surface the equip-or-bag prompt. Boss kills always produce a
# drop; regular enemies roll at ~10%.

func _make_character(level: int = 1) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	c.level = level
	return c

func _make_enemy(is_boss: bool = false) -> EnemyData:
	var e := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	e.xp_reward = 1
	e.is_boss = is_boss
	return e

func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng

func test_boss_kill_always_returns_non_null_item():
	# BOSS context has drop_chance 1.0 so every roll returns an item.
	# Test across several seeds to pin the guarantee — not a single lucky
	# seed.
	var c := _make_character(11)
	var enemy := _make_enemy(true)
	for s in [1, 2, 3, 17, 42, 99]:
		var item := KillRewardRouter.route_kill(
			c, enemy, null, "", null, null, null, _seeded_rng(s)
		)
		assert_not_null(item, "boss kill must always drop an item (seed %d)" % s)

func test_regular_enemy_kill_drop_rate_around_ten_percent():
	# Roll 1000 seeded kills and expect ~10% drops (±5% tolerance).
	# Pins the ENEMY context drop_chance constant through the router.
	var c := _make_character(11)
	var rng := _seeded_rng(12345)
	var drops := 0
	for i in 1000:
		var enemy := _make_enemy(false)
		var item := KillRewardRouter.route_kill(
			c, enemy, null, "", null, null, null, rng
		)
		if item != null:
			drops += 1
	# 10% expected, allow generous tolerance for RNG variance.
	assert_true(drops > 50, "expected >5%% drops, got %d" % drops)
	assert_true(drops < 150, "expected <15%% drops, got %d" % drops)

func test_regular_enemy_kill_produces_some_nulls():
	# Sanity: regular enemy kills are not 100% — at least some calls
	# across a small batch return null.
	var c := _make_character(1)
	var rng := _seeded_rng(7)
	var nulls := 0
	for i in 100:
		var enemy := _make_enemy(false)
		var item := KillRewardRouter.route_kill(
			c, enemy, null, "", null, null, null, rng
		)
		if item == null:
			nulls += 1
	assert_true(nulls > 50, "regular kills produce mostly nulls at 10%% rate")

func test_route_kill_solo_still_credits_gold():
	# Pin that adding the item drop seam did NOT break the existing gold
	# credit path. Existing test in test_gold_sources_combat.gd covers
	# the ledger; this asserts the cross-feature wiring is intact.
	var c := _make_character(1)
	var enemy := _make_enemy(false)
	enemy.gold_reward = 3
	var ledger := CurrencyLedger.new()
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, ledger, _seeded_rng(1))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 3,
		"gold credit unchanged by item drop seam")

func test_route_kill_solo_still_applies_xp():
	# Adding the item drop must not interfere with solo XP application.
	var c := _make_character(1)
	var enemy := _make_enemy(false)
	enemy.xp_reward = ProgressionSystem.xp_to_next_level(1)
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, null, _seeded_rng(1))
	assert_eq(c.level, 2, "solo path still levels up on threshold XP")

func test_route_kill_null_data_returns_null():
	# Null guard returns null cleanly — no crash.
	var enemy := _make_enemy(true)
	var item := KillRewardRouter.route_kill(null, enemy, null, "", null, null, null, _seeded_rng(1))
	assert_null(item)

func test_route_kill_null_enemy_returns_null():
	var c := _make_character(1)
	var item := KillRewardRouter.route_kill(c, null, null, "", null, null, null, _seeded_rng(1))
	assert_null(item)

# --- Luck gold bonus + rarity bump (PRD #85 / issue #90) ---------------------

func test_luck_gold_bonus_credited_on_kill():
	# Luck=3 + base gold=2 ⇒ ledger receives 5 total per kill.
	var c := _make_character(1)
	c.luck = 3
	var enemy := _make_enemy(false)
	enemy.gold_reward = 2
	var ledger := CurrencyLedger.new()
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, ledger, _seeded_rng(1))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 5,
		"base 2 + luck bonus 3 = 5")

func test_luck_zero_no_extra_gold():
	# Default character has luck=0 — only the base gold credits. Pin the
	# no-regression contract: existing kills without the Luck stat wired
	# still credit exactly enemy.gold_reward.
	var c := _make_character(1)
	assert_eq(c.luck, 0, "sanity: default character has zero luck")
	var enemy := _make_enemy(false)
	enemy.gold_reward = 2
	var ledger := CurrencyLedger.new()
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, ledger, _seeded_rng(1))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 2,
		"luck=0 path credits exactly base gold")

func test_null_ledger_with_luck_no_crash():
	# Null ledger short-circuits the entire gold path — luck gold can't
	# crash on the credit. Pin the AC.
	var c := _make_character(1)
	c.luck = 5
	var enemy := _make_enemy(false)
	enemy.gold_reward = 2
	# ledger arg omitted (null). Must not crash.
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, null, _seeded_rng(1))
	assert_true(true, "null ledger + non-zero luck did not crash")

func test_luck_rarity_bump_promotes_drop_under_saturated_luck():
	# luck=100 ⇒ bump chance 2.0 ⇒ randf() always < chance ⇒ every drop
	# bumps. Use a L1 character so the resolver gates everything down to
	# COMMON; after bump every dropped item must be RARE (or EPIC if the
	# bump pool offered EPIC — not possible from COMMON→next-tier).
	var c := _make_character(1)
	c.luck = 100
	var enemy := _make_enemy(true)  # boss ⇒ guaranteed drop
	for s in [1, 2, 3, 17, 42]:
		var item: ItemData = KillRewardRouter.route_kill(
			c, enemy, null, "", null, null, null, _seeded_rng(s)
		)
		assert_not_null(item, "seed %d: boss drop" % s)
		assert_eq(item.rarity, ItemData.Rarity.RARE,
			"seed %d: COMMON drop bumped to RARE under saturated luck" % s)

func test_luck_rarity_bump_noop_when_drop_already_epic():
	# L11 boss + saturated luck. If the resolver rolls an EPIC, the bump
	# must be a no-op (no tier above EPIC). Sweep seeds and assert that
	# EPIC outputs are still EPIC (and never null-out due to a bad pool
	# lookup).
	var c := _make_character(11)
	c.luck = 100
	var enemy := _make_enemy(true)
	var saw_epic := false
	for s in [1, 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67]:
		var item: ItemData = KillRewardRouter.route_kill(
			c, enemy, null, "", null, null, null, _seeded_rng(s)
		)
		assert_not_null(item, "seed %d: boss drop never null" % s)
		# Whatever rarity comes out, EPIC stays EPIC (no overflow / null).
		if item.rarity == ItemData.Rarity.EPIC:
			saw_epic = true
	assert_true(saw_epic, "sweep covered at least one EPIC outcome")

func test_luck_does_not_affect_drop_when_no_item_dropped():
	# Regular enemy + low drop rate + luck > 0 must NOT manufacture an
	# item out of a resolver miss — the bump operates on a non-null
	# resolver result only.
	var c := _make_character(1)
	c.luck = 100  # saturated — would always bump IF there were an item
	var rng := _seeded_rng(7)
	var nulls := 0
	for i in 50:
		var enemy := _make_enemy(false)
		var item := KillRewardRouter.route_kill(
			c, enemy, null, "", null, null, null, rng
		)
		if item == null:
			nulls += 1
	assert_true(nulls > 0,
		"saturated luck does not invent items from a missed resolver roll")

func test_route_kill_null_rng_does_not_crash():
	# The resolver allocates a fresh RNG when caller passes null. Pins
	# that the router doesn't crash on the pre-wiring code path.
	var c := _make_character(11)
	var enemy := _make_enemy(true)
	var item := KillRewardRouter.route_kill(c, enemy, null, "", null, null, null, null)
	# Boss => always non-null even with a default RNG.
	assert_not_null(item)
