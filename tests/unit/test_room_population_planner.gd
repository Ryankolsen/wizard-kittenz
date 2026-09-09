extends GutTest

# Pure module: given an RNG + room type, return the list of enemy kinds the
# generator should stamp on the room. Standard combat rooms roll ~50/50 single
# vs multi (count uniform 2..6 for multi). Boss = exactly one. Start/bar/powerup
# = empty.

func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r

func test_core_wiring_room_types_return_expected_shapes():
	# Standard -> non-empty array of valid kinds, drawn from the default
	# floor's (floor 1, tier 1) kind pool.
	var tier := DungeonFloorTier.for_floor(1)
	var standard_kinds: Array = RoomPopulationPlanner.plan_for_room_type(_rng(1), Room.TYPE_STANDARD)
	assert_true(standard_kinds.size() >= 1, "standard room produces at least one kind")
	for k in standard_kinds:
		assert_true(tier.kind_pool.has(k),
			"standard kind %s in floor 1 tier pool" % [k])
	# Boss -> exactly one kind.
	var boss_kinds: Array = RoomPopulationPlanner.plan_for_room_type(_rng(1), Room.TYPE_BOSS)
	assert_eq(boss_kinds.size(), 1, "boss room produces exactly one kind")
	# Non-combat -> empty.
	for t in [Room.TYPE_START, Room.TYPE_BAR, Room.TYPE_POWERUP]:
		var arr: Array = RoomPopulationPlanner.plan_for_room_type(_rng(1), t)
		assert_eq(arr.size(), 0, "%s room produces empty kinds" % t)

func test_single_vs_multi_split_is_roughly_50_50():
	# Sample 2000 standard rooms with a seeded RNG at floor 15 (tier 3).
	# Fraction returning exactly one kind should sit in [0.40, 0.60].
	var tier := DungeonFloorTier.for_floor(15)
	var rng := _rng(20260613)
	var samples := 2000
	var single_count := 0
	for _i in range(samples):
		var kinds: Array = RoomPopulationPlanner.plan_for_room_type(rng, Room.TYPE_STANDARD, 15)
		if kinds.size() == 1:
			single_count += 1
		else:
			assert_between(kinds.size(), tier.mob_min, tier.mob_max,
				"multi-mob count out of range")
	var fraction := float(single_count) / float(samples)
	assert_between(fraction, 0.40, 0.60,
		"single-mob fraction %f should be ~0.5" % fraction)

func test_multi_count_range_covers_2_to_6_and_kinds_are_from_roster():
	# Tier-parametrized: one floor per tier band, sampled at scale.
	for floor_number in [3, 8, 15, 25]:
		var tier := DungeonFloorTier.for_floor(floor_number)
		var rng := _rng(20260613)
		var seen_counts: Dictionary = {}
		for _i in range(2000):
			var kinds: Array = RoomPopulationPlanner.plan_for_room_type(rng, Room.TYPE_STANDARD, floor_number)
			assert_between(kinds.size(), 1, tier.mob_max,
				"floor %d: kind count out of bounds" % floor_number)
			if kinds.size() >= tier.mob_min:
				seen_counts[kinds.size()] = seen_counts.get(kinds.size(), 0) + 1
			for k in kinds:
				assert_true(tier.kind_pool.has(k),
					"floor %d: kind %s in tier pool" % [floor_number, k])
		for c in range(tier.mob_min, tier.mob_max + 1):
			assert_true(seen_counts.has(c),
				"floor %d: count %d should appear in multi-mob samples" % [floor_number, c])

func test_standard_room_draws_from_tier_kind_pool_and_density():
	# Core wiring: floor 3 (tier 1) standard-room draws respect both the
	# tier's mob density band and its kind pool.
	var tier := DungeonFloorTier.for_floor(3)
	for seed in [1, 7, 42, 1234, 99999]:
		var p: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(_rng(seed), Room.TYPE_STANDARD, 3)
		var kinds: Array = p["kinds"]
		assert_between(kinds.size(), tier.mob_min, tier.mob_max,
			"seed %d: count within floor 3 tier band" % seed)
		for k in kinds:
			assert_true(tier.kind_pool.has(k),
				"seed %d: kind %s in floor 3 tier pool" % [seed, k])

func test_boss_placeholder_still_draws_from_full_roster_regardless_of_floor():
	# Boss placeholder slot ignores floor tier kind-pool gating; it draws
	# from the full 5-kind roster even at floor 3 (tier 1's pool is 3 kinds).
	var tier := DungeonFloorTier.for_floor(3)
	var saw_kind_outside_tier_pool := false
	for seed in [1, 7, 42, 1234, 99999, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12]:
		var p: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(_rng(seed), Room.TYPE_BOSS, 3)
		var kinds: Array = p["kinds"]
		assert_eq(kinds.size(), 1, "seed %d: boss produces exactly one kind" % seed)
		assert_true(DungeonGenerator.STANDARD_ENEMY_KINDS.has(kinds[0]),
			"seed %d: boss kind in full roster" % seed)
		if not tier.kind_pool.has(kinds[0]):
			saw_kind_outside_tier_pool = true
	assert_true(saw_kind_outside_tier_pool,
		"boss placeholder draw should reach kinds outside floor 3's tier pool at least once")

func test_seed_stability():
	# Two RNGs seeded identically at the same floor must yield identical
	# kind lists per call.
	var a := _rng(424242)
	var b := _rng(424242)
	for _i in range(50):
		var ka: Array = RoomPopulationPlanner.plan_for_room_type(a, Room.TYPE_STANDARD, 7)
		var kb: Array = RoomPopulationPlanner.plan_for_room_type(b, Room.TYPE_STANDARD, 7)
		assert_eq(ka, kb, "same seed -> same kinds list")

# --- elites (PRD #376 / issue #380) ----------------------------------------

func test_elite_roll_is_deterministic():
	# Same seed → identical elite flag + bonus sequences. Host and clients
	# need this to agree on which spawns are elite without a sync packet.
	var a := _rng(7777)
	var b := _rng(7777)
	for _i in range(60):
		var pa: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(a, Room.TYPE_STANDARD)
		var pb: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(b, Room.TYPE_STANDARD)
		assert_eq(pa["kinds"], pb["kinds"], "kinds match")
		assert_eq(pa["elites"], pb["elites"], "elites match")
		assert_eq(pa["elite_bonuses"], pb["elite_bonuses"], "bonuses match")

func test_elite_frequency_about_ten_percent():
	# Over a large fixed-seed sample, the elite fraction sits within tolerance
	# of ELITE_CHANCE. Sample many rooms to smooth the roll variance.
	var rng := _rng(20260613)
	var total_spawns := 0
	var elite_count := 0
	for _i in range(2000):
		var p: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(rng, Room.TYPE_STANDARD)
		var elites: Array = p["elites"]
		total_spawns += elites.size()
		for is_elite in elites:
			if is_elite:
				elite_count += 1
	var fraction := float(elite_count) / float(total_spawns)
	assert_between(fraction, 0.07, 0.13,
		"elite fraction %f should be ~%f" % [fraction, RoomPopulationPlanner.ELITE_CHANCE])

func test_boss_room_never_elite():
	# Bosses are never elite. The elite arrays for a boss room are length-1
	# and all-false.
	for seed in [1, 7, 42, 1234, 99999]:
		var p: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(_rng(seed), Room.TYPE_BOSS)
		assert_eq(p["kinds"].size(), 1)
		assert_eq(p["elites"].size(), 1)
		assert_false(p["elites"][0], "seed %d boss is not elite" % seed)
		assert_eq(p["elite_bonuses"][0], 0)

func test_elite_level_bonus_in_range():
	# Every elite's bonus is in [3, 5]. Non-elites carry 0.
	var rng := _rng(424242)
	var seen_elite := false
	for _i in range(500):
		var p: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(rng, Room.TYPE_STANDARD)
		var elites: Array = p["elites"]
		var bonuses: Array = p["elite_bonuses"]
		assert_eq(elites.size(), bonuses.size(), "parallel array sizes match")
		for j in range(elites.size()):
			if elites[j]:
				seen_elite = true
				assert_between(bonuses[j],
					RoomPopulationPlanner.ELITE_LEVEL_BONUS_MIN,
					RoomPopulationPlanner.ELITE_LEVEL_BONUS_MAX,
					"elite bonus in [3, 5]")
			else:
				assert_eq(bonuses[j], 0, "non-elite bonus is 0")
	assert_true(seen_elite, "sample large enough to see at least one elite")
