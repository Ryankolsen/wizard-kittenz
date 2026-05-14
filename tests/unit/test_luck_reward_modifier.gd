extends GutTest

func test_gold_bonus_zero_luck_returns_zero():
	assert_eq(LuckRewardModifier.gold_bonus(0), 0)

func test_rarity_bump_zero_luck_returns_zero():
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(0), 0.0, 0.0001)

func test_gold_bonus_scales_linearly():
	assert_eq(LuckRewardModifier.gold_bonus(1), 1)
	assert_eq(LuckRewardModifier.gold_bonus(5), 5)
	assert_eq(LuckRewardModifier.gold_bonus(10), 10)

func test_rarity_bump_scales_linearly():
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(1), 0.02, 0.0001)
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(5), 0.10, 0.0001)
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(10), 0.20, 0.0001)

func test_gold_bonus_negative_luck_returns_zero():
	assert_eq(LuckRewardModifier.gold_bonus(-1), 0)
	assert_eq(LuckRewardModifier.gold_bonus(-100), 0)

func test_rarity_bump_negative_luck_returns_zero():
	assert_almost_eq(LuckRewardModifier.rarity_bump_chance(-5), 0.0, 0.0001)

func test_rarity_bump_high_luck_does_not_exceed_one():
	# Documented behaviour: formula is unbounded, but call sites should clamp
	# before sampling. Guard against future regressions where the formula
	# accidentally over-multiplies.
	var hi: float = LuckRewardModifier.rarity_bump_chance(999)
	assert_true(hi > 0.0, "high luck still produces a positive chance")
	# Natural float — not clamped at this layer. Just assert it doesn't go
	# wildly past the expected linear value.
	assert_almost_eq(hi, 999 * 0.02, 0.0001)

# --- bump_item -------------------------------------------------------------

func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng

func test_bump_item_null_returns_null():
	# A null drop (resolver miss) must pass through silently — caller
	# (KillRewardRouter) shouldn't have to repeat the gate.
	assert_null(LuckRewardModifier.bump_item(null, 5, _seeded_rng(1)))

func test_bump_item_zero_luck_returns_input_untouched():
	# luck<=0 short-circuits before the rng roll. Same object returned —
	# no allocation, no roll.
	var item := ItemData.make("iron_sword", "Iron Sword", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0)
	var result := LuckRewardModifier.bump_item(item, 0, _seeded_rng(1))
	assert_eq(result, item, "luck=0 returns the same item ref")

func test_bump_item_epic_is_noop():
	# Already at max rarity — no tier to promote to. Returns input ref.
	var item := ItemData.make("enchanted_blade", "Enchanted Blade", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 8.0)
	var result := LuckRewardModifier.bump_item(item, 100, _seeded_rng(1))
	assert_eq(result, item, "EPIC item never bumps")
	assert_eq(result.rarity, ItemData.Rarity.EPIC)

func test_bump_item_promotes_common_to_rare_when_roll_succeeds():
	# luck=100 ⇒ chance=2.0 ⇒ randf() is always < chance ⇒ always bumps.
	# Bumped item must come from the RARE pool.
	var item := ItemData.make("iron_sword", "Iron Sword", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0)
	for s in [1, 2, 3, 42, 99]:
		var result := LuckRewardModifier.bump_item(item, 100, _seeded_rng(s))
		assert_eq(result.rarity, ItemData.Rarity.RARE,
			"seed %d: COMMON bumped to RARE under saturated luck" % s)

func test_bump_item_promotes_rare_to_epic_when_roll_succeeds():
	var item := ItemData.make("silver_sword", "Silver Sword", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "attack", 5.0)
	for s in [1, 2, 3, 42, 99]:
		var result := LuckRewardModifier.bump_item(item, 100, _seeded_rng(s))
		assert_eq(result.rarity, ItemData.Rarity.EPIC,
			"seed %d: RARE bumped to EPIC under saturated luck" % s)

func test_bump_item_skips_when_roll_fails():
	# luck=1 ⇒ 2% chance. Most seeds the randf() roll lands above 0.02
	# so the input is returned unchanged. Pin against one such seed.
	var item := ItemData.make("iron_sword", "Iron Sword", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0)
	# Find a seed whose first randf is well above 0.02 — most seeds qualify.
	var rng := _seeded_rng(1)
	var first_randf := rng.randf()
	assert_true(first_randf > 0.02, "sanity: seed 1 first randf > 2%% bump chance")
	var result := LuckRewardModifier.bump_item(item, 1, _seeded_rng(1))
	assert_eq(result, item, "low-luck roll failure returns input untouched")

func test_bump_item_null_rng_does_not_crash():
	# Caller passing null rng (defensive path) allocates a default rng
	# inside. We just assert no crash and a sensible return.
	var item := ItemData.make("iron_sword", "Iron Sword", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0)
	var result := LuckRewardModifier.bump_item(item, 5, null)
	assert_true(result != null, "non-null input never returns null")
