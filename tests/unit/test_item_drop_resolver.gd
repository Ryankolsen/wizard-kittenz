extends GutTest

func _make_rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng

func test_boss_returns_non_null():
	var rng := _make_rng(1)
	var item := ItemDropResolver.resolve(1, ItemDropResolver.Context.BOSS, rng)
	assert_not_null(item)

func test_boss_always_drops_across_20_calls():
	var rng := _make_rng(42)
	for i in 20:
		var item := ItemDropResolver.resolve(1, ItemDropResolver.Context.BOSS, rng)
		assert_not_null(item, "boss drop %d was null" % i)

func test_level_1_never_rare_or_epic():
	var rng := _make_rng(7)
	for i in 100:
		var item := ItemDropResolver.resolve(1, ItemDropResolver.Context.ENEMY, rng)
		if item != null:
			assert_eq(item.rarity, ItemData.Rarity.COMMON, "non-common dropped at level 1")

func test_level_6_can_drop_rare_but_not_epic():
	var rng := _make_rng(123)
	var saw_rare := false
	for i in 200:
		var item := ItemDropResolver.resolve(6, ItemDropResolver.Context.BOSS, rng)
		assert_not_null(item)
		assert_ne(item.rarity, ItemData.Rarity.EPIC, "epic dropped at level 6")
		if item.rarity == ItemData.Rarity.RARE:
			saw_rare = true
	assert_true(saw_rare, "no rare in 200 rolls at level 6")

func test_level_11_can_drop_epic():
	var rng := _make_rng(99)
	var saw_epic := false
	for i in 500:
		var item := ItemDropResolver.resolve(11, ItemDropResolver.Context.BOSS, rng)
		if item != null and item.rarity == ItemData.Rarity.EPIC:
			saw_epic = true
			break
	assert_true(saw_epic, "no epic in 500 rolls at level 11")

func test_enemy_drop_rate_within_tolerance():
	var rng := _make_rng(2024)
	var drops := 0
	var total := 1000
	for i in total:
		var item := ItemDropResolver.resolve(1, ItemDropResolver.Context.ENEMY, rng)
		if item != null:
			drops += 1
	var rate := float(drops) / float(total)
	assert_almost_eq(rate, 0.10, 0.05, "drop rate out of tolerance: %f" % rate)

func test_null_rng_does_not_crash():
	for ctx in [ItemDropResolver.Context.ENEMY, ItemDropResolver.Context.BOSS, ItemDropResolver.Context.CHEST_STANDARD, ItemDropResolver.Context.CHEST_RARE]:
		ItemDropResolver.resolve(1, ctx, null)
	assert_true(true)

func test_returned_item_rarity_matches_catalog():
	var rng := _make_rng(555)
	for i in 100:
		var item := ItemDropResolver.resolve(11, ItemDropResolver.Context.BOSS, rng)
		assert_not_null(item)
		var found := ItemCatalog.find(item.id)
		assert_not_null(found, "item %s not in catalog" % item.id)
		assert_eq(found.rarity, item.rarity)
