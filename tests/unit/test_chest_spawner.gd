extends GutTest

# Tests for ChestSpawner — pure-data placement layer for PRD #217 / issue #219.
# Builds dungeons inline like test_room_spawn_planner.gd; uses seeded RNG like
# test_chest_loot_currency.gd._seeded_rng.

func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng

# Builds a dungeon with 1 start + `standard_count` standard rooms + 1 boss.
# Rooms are connected linearly so connectivity invariants hold; the spawner
# doesn't read connections but the dungeon ought to be well-formed.
func _make_dungeon(standard_count: int) -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	d.add_room(start)
	d.start_id = 0
	var prev_id := 0
	for i in range(standard_count):
		var rid := i + 1
		var r := Room.make(rid, Room.TYPE_STANDARD)
		r.enemy_kind = EnemyData.EnemyKind.ANGRY_PIGEON
		d.add_room(r)
		d.get_room(prev_id).connections.append(rid)
		prev_id = rid
	var boss_id := standard_count + 1
	var boss := Room.make(boss_id, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	d.add_room(boss)
	d.get_room(prev_id).connections.append(boss_id)
	d.boss_id = boss_id
	return d

func test_plan_returns_target_count_placements():
	var d := _make_dungeon(6)
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	assert_eq(placements.size(), ChestSpawner.TARGET_COUNT)

func test_placement_struct_has_room_position_and_chest():
	var d := _make_dungeon(6)
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	var first: Dictionary = placements[0]
	assert_true(first.has("room_id"))
	assert_true(first.has("position"))
	assert_true(first.has("chest"))
	assert_true(first["position"] is Vector2)
	assert_not_null(d.get_room(first["room_id"]), "room_id refers to a real room")
	var chest: Chest = first["chest"]
	assert_eq(chest.kind, Chest.Kind.STANDARD)

func test_start_room_is_never_chosen():
	var d := _make_dungeon(6)
	for seed_val in range(20):
		var placements := ChestSpawner.plan(d, _seeded_rng(seed_val))
		for p in placements:
			assert_ne(p["room_id"], d.start_id, "start room must be excluded (seed=%d)" % seed_val)

func test_bar_room_is_never_chosen():
	# Bar rooms host the tavern entrance (a large door footprint). Spawning
	# chests on top of it looks broken and blocks the entrance — exclude bar
	# rooms from chest placement the same way start rooms are excluded.
	var d := _make_dungeon(6)
	var bar_id := 99
	var bar := Room.make(bar_id, Room.TYPE_BAR)
	d.add_room(bar)
	d.get_room(1).connections.append(bar_id)
	for seed_val in range(20):
		var placements := ChestSpawner.plan(d, _seeded_rng(seed_val))
		for p in placements:
			assert_ne(p["room_id"], bar_id, "bar room must be excluded (seed=%d)" % seed_val)

func test_same_seed_produces_identical_placements():
	var d := _make_dungeon(6)
	var a := ChestSpawner.plan(d, _seeded_rng(42))
	var b := ChestSpawner.plan(d, _seeded_rng(42))
	assert_eq(a.size(), b.size())
	for i in range(a.size()):
		assert_eq(a[i]["room_id"], b[i]["room_id"])
		assert_eq(a[i]["position"], b[i]["position"])

func test_different_seeds_produce_different_placements():
	var d := _make_dungeon(6)
	var a := ChestSpawner.plan(d, _seeded_rng(1))
	var b := ChestSpawner.plan(d, _seeded_rng(2))
	var any_diff := false
	for i in range(a.size()):
		if a[i]["room_id"] != b[i]["room_id"] or a[i]["position"] != b[i]["position"]:
			any_diff = true
			break
	assert_true(any_diff, "different seeds should yield at least one different placement")

func test_plan_with_only_start_room_returns_empty():
	var d := Dungeon.new()
	d.add_room(Room.make(0, Room.TYPE_START))
	d.start_id = 0
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	assert_eq(placements.size(), 0)

func test_below_threshold_all_chests_are_standard():
	var d := _make_dungeon(8)
	d.depth = ChestSpawner.RARE_UNLOCK_DEPTH - 1
	for seed_val in range(5):
		var placements := ChestSpawner.plan(d, _seeded_rng(seed_val))
		for p in placements:
			var c: Chest = p["chest"]
			assert_eq(c.kind, Chest.Kind.STANDARD,
				"below-threshold dungeon must never roll RARE (seed=%d)" % seed_val)

func test_at_or_above_threshold_can_roll_rare():
	var d := _make_dungeon(8)
	d.depth = ChestSpawner.RARE_UNLOCK_DEPTH
	var rare_count := 0
	for seed_val in range(1, 101):
		var placements := ChestSpawner.plan(d, _seeded_rng(seed_val))
		for p in placements:
			var c: Chest = p["chest"]
			if c.kind == Chest.Kind.RARE:
				rare_count += 1
	assert_true(rare_count > 0,
		"at/above threshold, at least one RARE must roll over 500 placements (got %d)" % rare_count)

func test_rare_rate_matches_configured_chance_within_tolerance():
	var d := _make_dungeon(8)
	d.depth = ChestSpawner.RARE_UNLOCK_DEPTH
	var rare_count := 0
	var total := 0
	for seed_val in range(1, 101):
		var placements := ChestSpawner.plan(d, _seeded_rng(seed_val))
		for p in placements:
			total += 1
			var c: Chest = p["chest"]
			if c.kind == Chest.Kind.RARE:
				rare_count += 1
	var rate: float = float(rare_count) / float(total)
	var delta: float = abs(rate - ChestSpawner.RARE_CHANCE_AFTER_UNLOCK)
	assert_true(delta <= 0.1,
		"rare rate %.3f should be within 0.1 of configured %.3f" % [rate, ChestSpawner.RARE_CHANCE_AFTER_UNLOCK])

func test_same_seed_at_threshold_produces_identical_kinds():
	var d := _make_dungeon(6)
	d.depth = ChestSpawner.RARE_UNLOCK_DEPTH
	var a := ChestSpawner.plan(d, _seeded_rng(7))
	var b := ChestSpawner.plan(d, _seeded_rng(7))
	assert_eq(a.size(), b.size())
	for i in range(a.size()):
		var ca: Chest = a[i]["chest"]
		var cb: Chest = b[i]["chest"]
		assert_eq(ca.kind, cb.kind, "kind must be deterministic per seed at index %d" % i)
		assert_eq(a[i]["room_id"], b[i]["room_id"])
		assert_eq(a[i]["position"], b[i]["position"])

func test_chest_ids_are_deterministic_from_spawner():
	# Slice 4 (#221) co-op sync: both clients run plan() with the same
	# (dungeon, seed) and must agree on chest_id per placement so a remote
	# open lands on the right local entity.
	var d := _make_dungeon(6)
	var a := ChestSpawner.plan(d, _seeded_rng(5))
	var b := ChestSpawner.plan(d, _seeded_rng(5))
	assert_eq(a.size(), b.size())
	for i in range(a.size()):
		assert_true(a[i].has("chest_id"), "placement carries chest_id")
		assert_eq(a[i]["chest_id"], b[i]["chest_id"],
			"chest_id must match across runs at index %d" % i)
	# IDs are also unique within a single plan() call so the wire-side
	# lookup table can't collide.
	var seen: Dictionary = {}
	for p in a:
		var cid: String = p["chest_id"]
		assert_false(seen.has(cid), "chest_id %s appears twice in one plan" % cid)
		seen[cid] = true


func test_rare_unlock_constants_are_set():
	assert_true(ChestSpawner.RARE_UNLOCK_DEPTH >= 1,
		"RARE_UNLOCK_DEPTH must be >= 1 so depth-0 (first dungeon) stays gold-only")
	assert_true(ChestSpawner.RARE_CHANCE_AFTER_UNLOCK > 0.0 and ChestSpawner.RARE_CHANCE_AFTER_UNLOCK < 1.0,
		"RARE_CHANCE_AFTER_UNLOCK must be strictly between 0 and 1")
