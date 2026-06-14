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

func _general_count(placements: Array) -> int:
	var n := 0
	for p in placements:
		if not String(p["chest_id"]).begins_with("boss_chest_"):
			n += 1
	return n

func test_plan_returns_scaled_general_count_plus_boss():
	# Small dungeon: 6 standard + 1 boss = 7 candidates. Below the per-N-rooms
	# threshold it clamps to MIN_GENERAL_CHESTS.
	var d := _make_dungeon(6)
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	var expected_general := ChestSpawner.general_chest_count(7)
	assert_eq(_general_count(placements), expected_general)
	# 3 boss-room (PRD #311 / issue #313).
	assert_eq(placements.size(), expected_general + 3)

func test_general_count_scales_with_room_count():
	# Regression for the expanded dungeon (#: 100-150 rooms). A big dungeon must
	# yield far more than the old fixed 5 general chests so a crawl reliably
	# encounters loot. At ~1 per 10 candidate rooms a 124-candidate dungeon
	# should land around 12 general chests.
	var big := _make_dungeon(123)  # 123 standard + 1 boss = 124 candidates
	var placements := ChestSpawner.plan(big, _seeded_rng(1))
	var general := _general_count(placements)
	assert_eq(general, ChestSpawner.general_chest_count(124))
	assert_true(general >= 10 and general <= 15,
		"124-candidate dungeon should yield ~12 general chests, got %d" % general)

func test_general_count_helper_density_and_floor():
	# 1 general chest per CHEST_PER_N_ROOMS candidate rooms, floored at
	# MIN_GENERAL_CHESTS so tiny dungeons still feel rewarding.
	assert_eq(ChestSpawner.general_chest_count(0), ChestSpawner.MIN_GENERAL_CHESTS)
	assert_eq(ChestSpawner.general_chest_count(10), ChestSpawner.MIN_GENERAL_CHESTS)
	assert_eq(ChestSpawner.general_chest_count(100), 10)
	assert_eq(ChestSpawner.general_chest_count(150), 15)

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
			# Boss-room rewards (#313) are unconditional RARE/BOSS_ITEM and
			# don't participate in the general-pool depth gate.
			if String(p["chest_id"]).begins_with("boss_chest_"):
				continue
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
			# Boss-room placements (#313) are unconditional and would skew
			# the general-pool rate — exclude them from this measurement.
			if String(p["chest_id"]).begins_with("boss_chest_"):
				continue
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


# --- Boss-room reward chests (PRD #311 / issue #313) -------------------------

func _boss_placements(placements: Array) -> Array:
	var out: Array = []
	for p in placements:
		if String(p["chest_id"]).begins_with("boss_chest_"):
			out.append(p)
	return out

func test_spawner_returns_general_plus_3_placements_for_dungeon_with_boss():
	var d := _make_dungeon(6)  # 6 standard + 1 boss = 7 candidates
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	assert_eq(placements.size(), ChestSpawner.general_chest_count(7) + 3)

func test_spawner_boss_placements_have_correct_ids_and_kinds():
	var d := _make_dungeon(6)
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	var boss := _boss_placements(placements)
	assert_eq(boss.size(), 3)
	var ids: Array = []
	for p in boss:
		ids.append(p["chest_id"])
		assert_eq(p["room_id"], d.boss_id, "boss placement must live in boss_id room")
	assert_true(ids.has("boss_chest_0"))
	assert_true(ids.has("boss_chest_1"))
	assert_true(ids.has("boss_chest_2"))
	var by_id: Dictionary = {}
	for p in boss:
		by_id[p["chest_id"]] = p["chest"]
	assert_eq((by_id["boss_chest_0"] as Chest).kind, Chest.Kind.BOSS_ITEM)
	assert_eq((by_id["boss_chest_1"] as Chest).kind, Chest.Kind.RARE)
	assert_eq((by_id["boss_chest_2"] as Chest).kind, Chest.Kind.RARE)

func test_spawner_boss_placements_deterministic_under_seed():
	var d := _make_dungeon(6)
	var a := _boss_placements(ChestSpawner.plan(d, _seeded_rng(13)))
	var b := _boss_placements(ChestSpawner.plan(d, _seeded_rng(13)))
	assert_eq(a.size(), 3)
	assert_eq(b.size(), 3)
	for i in range(a.size()):
		assert_eq(a[i]["chest_id"], b[i]["chest_id"])
		assert_eq(a[i]["position"], b[i]["position"])
		assert_eq((a[i]["chest"] as Chest).kind, (b[i]["chest"] as Chest).kind)

func test_spawner_skips_boss_placements_when_no_boss_room():
	# A dungeon without a valid boss_id (the Dungeon default is -1) must
	# yield only the general pool — no boss_chest_ placements, no crash.
	var d := Dungeon.new()
	d.add_room(Room.make(0, Room.TYPE_START))
	d.start_id = 0
	d.add_room(Room.make(1, Room.TYPE_STANDARD))
	d.get_room(0).connections.append(1)
	# d.boss_id stays at -1 (the default). 1 standard room = 1 candidate.
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	assert_eq(placements.size(), ChestSpawner.general_chest_count(1))
	for p in placements:
		assert_false(String(p["chest_id"]).begins_with("boss_chest_"),
			"no boss placements when boss_id is invalid")

func test_spawner_boss_item_chest_depth_matches_floor_number():
	# BOSS_ITEM chest carries floor_number (dungeon.depth + 1) so its open()
	# can route through ItemDropResolver.rarity_for_floor without an extra
	# parameter at the ChestEntity layer.
	var d := _make_dungeon(6)
	d.depth = 5  # dungeons_completed = 5, so floor_number = 6
	var placements := ChestSpawner.plan(d, _seeded_rng(1))
	for p in placements:
		if p["chest_id"] == "boss_chest_0":
			assert_eq((p["chest"] as Chest).depth, 6)
			return
	fail_test("expected a boss_chest_0 placement")


func test_rare_unlock_constants_are_set():
	assert_true(ChestSpawner.RARE_UNLOCK_DEPTH >= 1,
		"RARE_UNLOCK_DEPTH must be >= 1 so depth-0 (first dungeon) stays gold-only")
	assert_true(ChestSpawner.RARE_CHANCE_AFTER_UNLOCK > 0.0 and ChestSpawner.RARE_CHANCE_AFTER_UNLOCK < 1.0,
		"RARE_CHANCE_AFTER_UNLOCK must be strictly between 0 and 1")
