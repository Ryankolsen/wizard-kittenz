extends GutTest

# --- Issue tests (5 acceptance scenarios) ---

func test_generate_returns_min_to_max_rooms():
	# Issue test 1: DungeonGenerator.generate() returns a graph with between
	# MIN_ROOMS and MAX_ROOMS nodes inclusive. Run a handful of seeds to cover
	# the range, not just one draw.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		assert_between(d.size(), DungeonGenerator.MIN_ROOMS, DungeonGenerator.MAX_ROOMS,
			"seed %d produced %d rooms (expected %d..%d)" % [s, d.size(), DungeonGenerator.MIN_ROOMS, DungeonGenerator.MAX_ROOMS])

func test_room_count_band_is_100_to_150():
	# #370: scaled dungeon lives in the ~100–150 room band.
	assert_gte(DungeonGenerator.MIN_ROOMS, 100,
		"MIN_ROOMS %d should be >= 100" % DungeonGenerator.MIN_ROOMS)
	assert_lte(DungeonGenerator.MAX_ROOMS, 150,
		"MAX_ROOMS %d should be <= 150" % DungeonGenerator.MAX_ROOMS)

func test_structural_guarantees_at_scale():
	# #370: across seeds, large dungeons still have exactly 1 start, 1 bar,
	# 3 power-up, 1 boss, with growth landing in standard combat rooms.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		var counts := {Room.TYPE_START: 0, Room.TYPE_BAR: 0, Room.TYPE_POWERUP: 0, Room.TYPE_BOSS: 0, Room.TYPE_STANDARD: 0}
		for r in d.rooms:
			counts[r.type] = counts.get(r.type, 0) + 1
		assert_eq(counts[Room.TYPE_START], 1, "seed %d: exactly 1 start" % s)
		assert_eq(counts[Room.TYPE_BAR], 1, "seed %d: exactly 1 bar" % s)
		assert_eq(counts[Room.TYPE_POWERUP], 3, "seed %d: exactly 3 power-up" % s)
		assert_eq(counts[Room.TYPE_BOSS], 1, "seed %d: exactly 1 boss" % s)
		assert_gte(counts[Room.TYPE_STANDARD], 90,
			"seed %d: at least 90 standard rooms, got %d" % [s, counts[Room.TYPE_STANDARD]])

func test_full_reachability_and_terminal_boss_at_scale():
	# #370: every room reachable from start and boss has no outgoing edges
	# at the larger scale.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		var visited := d.bfs_from_start()
		assert_eq(visited.size(), d.size(),
			"seed %d: BFS visited %d / %d rooms" % [s, visited.size(), d.size()])
		assert_eq(d.boss_room().connections.size(), 0,
			"seed %d: boss is terminal" % s)

func test_every_dungeon_has_at_least_four_standard_combat_rooms():
	# Minimum mob requirement: every dungeon must have at least 4 standard
	# combat rooms so the player fights at least 4 mobs + the boss per level.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		var standard_count := 0
		for r in d.rooms:
			if r.type == Room.TYPE_STANDARD:
				standard_count += 1
		assert_gte(standard_count, 4,
			"seed %d produced only %d standard rooms (minimum 4 required)" % [s, standard_count])

func test_exactly_one_boss_room():
	# Issue test 2: exactly one node has type == "boss".
	for s in [1, 2, 3, 7, 42]:
		var d := DungeonGenerator.generate(s)
		var boss_count := 0
		for r in d.rooms:
			if r.type == Room.TYPE_BOSS:
				boss_count += 1
		assert_eq(boss_count, 1, "seed %d produced %d boss rooms (expected 1)" % [s, boss_count])

func test_every_room_reachable_from_start():
	# Issue test 3: BFS from start visits every node.
	for s in [1, 2, 3, 7, 42]:
		var d := DungeonGenerator.generate(s)
		var visited := d.bfs_from_start()
		assert_eq(visited.size(), d.size(),
			"seed %d: BFS visited %d / %d rooms" % [s, visited.size(), d.size()])

func test_different_seeds_produce_different_layouts():
	# Issue test 4: two graphs generated with different seeds do not produce
	# identical room type sequences.
	var a := DungeonGenerator.generate(1)
	var b := DungeonGenerator.generate(2)
	assert_ne(a.room_type_sequence(), b.room_type_sequence(),
		"distinct seeds should produce distinct layouts")

func test_boss_room_has_no_outgoing_edges():
	# Issue test 5: boss room is terminal (empty connections array).
	for s in [1, 2, 3, 7, 42]:
		var d := DungeonGenerator.generate(s)
		var boss := d.boss_room()
		assert_not_null(boss, "boss room exists")
		assert_eq(boss.connections.size(), 0,
			"seed %d: boss has %d outgoing edges (expected 0)" % [s, boss.connections.size()])

# --- Bar room (#180) ---

func test_exactly_one_bar_room_per_seed():
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		var bar_count := 0
		for r in d.rooms:
			if r.type == Room.TYPE_BAR:
				bar_count += 1
		assert_eq(bar_count, 1, "seed %d produced %d bar rooms (expected 1)" % [s, bar_count])

func test_bar_room_is_not_start_or_boss_and_has_two_outgoing_edges():
	for s in [1, 2, 3, 7, 42]:
		var d := DungeonGenerator.generate(s)
		var bar: Room = null
		for r in d.rooms:
			if r.type == Room.TYPE_BAR:
				bar = r
		assert_not_null(bar, "seed %d: bar room exists" % s)
		assert_ne(bar, d.start_room(), "seed %d: bar is not the start room" % s)
		assert_ne(bar, d.boss_room(), "seed %d: bar is not the boss room" % s)
		assert_eq(bar.connections.size(), 2,
			"seed %d: bar has %d outgoing edges (expected 2)" % [s, bar.connections.size()])

func test_bar_room_has_no_enemy_or_powerup_data():
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		for r in d.rooms:
			if r.type == Room.TYPE_BAR:
				assert_eq(r.enemy_kind, -1, "seed %d: bar has no enemy_kind" % s)
				assert_eq(r.power_up_type, "", "seed %d: bar has no power_up_type" % s)

func test_bar_room_is_not_adjacent_to_boss():
	# Adjacency = boss's parent in the spanning tree. The bar must not be
	# the parent of the boss (so players have at least one room between
	# the bar and the boss fight).
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		var boss := d.boss_room()
		for r in d.rooms:
			if r.type == Room.TYPE_BAR:
				assert_false(r.connections.has(boss.id),
					"seed %d: bar should not connect directly to boss" % s)

# --- Coverage beyond the 5 issue scenarios ---

func test_same_seed_is_deterministic():
	# Same non-zero seed must produce the same layout twice. Underpins the
	# seed-variance test (if seed=1 isn't deterministic, the variance test
	# is non-deterministic too).
	var a := DungeonGenerator.generate(42)
	var b := DungeonGenerator.generate(42)
	assert_eq(a.size(), b.size(), "size matches across re-runs")
	assert_eq(a.room_type_sequence(), b.room_type_sequence(), "type sequence matches")
	for i in range(a.size()):
		assert_eq(a.rooms[i].connections, b.rooms[i].connections,
			"room %d connections match across re-runs" % i)
		assert_eq(a.rooms[i].enemy_kind, b.rooms[i].enemy_kind,
			"room %d enemy_kind matches" % i)
		assert_eq(a.rooms[i].power_up_type, b.rooms[i].power_up_type,
			"room %d power_up_type matches" % i)

func test_unseeded_generate_does_not_collide():
	# Acceptance criterion: "No two consecutive runs produce identical
	# layouts". Unseeded -> randomize() -> distinct draws. Tiny non-zero
	# collision probability acceptable; assert the type sequences differ
	# across two consecutive calls.
	var a := DungeonGenerator.generate()
	var b := DungeonGenerator.generate()
	# Layouts can match by chance on 5-room runs (small space), but the
	# combination of size + type sequence + first parent assignment is
	# extremely unlikely to collide. Fall back to a stronger fingerprint.
	var fp_a := _fingerprint(a)
	var fp_b := _fingerprint(b)
	assert_ne(fp_a, fp_b, "unseeded consecutive runs should diverge")

func test_start_room_id_is_zero():
	var d := DungeonGenerator.generate(1)
	assert_eq(d.start_id, 0)
	assert_eq(d.start_room().type, Room.TYPE_START)

func test_boss_id_is_last():
	# Boss is added last in the algorithm; its id equals size - 1. Locks
	# the "boss is the terminal node by construction" invariant.
	var d := DungeonGenerator.generate(7)
	assert_eq(d.boss_id, d.size() - 1)

func test_boss_kind_matches_boss_roster_for_floor():
	# Boss kind is now a deterministic per-floor lookup (PRD #297, slice
	# #301): BossRoster.boss_for_floor(N).kind, not a random pool draw.
	# Seeded with different RNG seeds but the same floor — the boss kind
	# must not vary with the seed.
	for floor_n in [1, 2, 5, 10, 11]:
		var expected: int = BossRoster.boss_for_floor(floor_n).kind
		for s in [1, 7, 42, 100]:
			var d := DungeonGenerator.generate(s, floor_n)
			assert_eq(d.boss_room().enemy_kind, expected,
				"seed %d floor %d: boss kind should match BossRoster" % [s, floor_n])

func test_only_powerup_rooms_have_power_up_type():
	var d := DungeonGenerator.generate(42)
	for r in d.rooms:
		if r.type == Room.TYPE_POWERUP:
			assert_true(DungeonGenerator.POWER_UP_TYPES.has(r.power_up_type),
				"power-up room has a valid type, got '%s'" % r.power_up_type)
		else:
			assert_eq(r.power_up_type, "",
				"non-power-up room (type=%s) should have empty power_up_type" % r.type)

func test_exactly_one_of_each_powerup_type():
	# Every dungeon must contain exactly one room per power-up type — no more,
	# no less. A duplicate means a player gets two of one item and zero of
	# another; a missing type means they never see it in that run.
	for s in [1, 2, 3, 7, 42, 100, 9999]:
		var d := DungeonGenerator.generate(s)
		var type_counts: Dictionary = {}
		for r in d.rooms:
			if r.type == Room.TYPE_POWERUP:
				type_counts[r.power_up_type] = type_counts.get(r.power_up_type, 0) + 1
		assert_eq(type_counts.size(), DungeonGenerator.POWER_UP_TYPES.size(),
			"seed %d: expected %d distinct power-up types, got %d" % [
				s, DungeonGenerator.POWER_UP_TYPES.size(), type_counts.size()])
		for t in DungeonGenerator.POWER_UP_TYPES:
			assert_eq(type_counts.get(t, 0), 1,
				"seed %d: type '%s' should appear exactly once, got %d" % [
					s, t, type_counts.get(t, 0)])

func test_only_combat_rooms_have_enemy_kind():
	var d := DungeonGenerator.generate(42)
	for r in d.rooms:
		match r.type:
			Room.TYPE_START:
				assert_eq(r.enemy_kind, -1, "start room has no enemy")
			Room.TYPE_POWERUP:
				assert_eq(r.enemy_kind, -1, "power-up room has no enemy")
			Room.TYPE_STANDARD:
				assert_true(DungeonGenerator.STANDARD_ENEMY_KINDS.has(r.enemy_kind),
					"standard enemy_kind in pool")
			Room.TYPE_BOSS:
				assert_eq(r.enemy_kind, BossRoster.boss_for_floor(1).kind,
					"boss enemy_kind matches BossRoster (default floor=1)")
			Room.TYPE_BAR:
				assert_eq(r.enemy_kind, -1, "bar room has no enemy")

func test_get_room_returns_null_for_unknown_id():
	var d := DungeonGenerator.generate(1)
	assert_null(d.get_room(999), "unknown id returns null")
	assert_null(d.get_room(-1), "negative id returns null")

func test_room_ids_are_unique_and_dense():
	# Algorithm: ids are 0..N-1 with no gaps. Locks the invariant so a
	# future change to the generator can't accidentally introduce sparse
	# or duplicate ids without breaking this test.
	var d := DungeonGenerator.generate(13)
	var seen: Dictionary = {}
	for r in d.rooms:
		assert_false(seen.has(r.id), "duplicate id %d" % r.id)
		seen[r.id] = true
	for i in range(d.size()):
		assert_true(seen.has(i), "missing id %d (expected dense 0..%d)" % [i, d.size() - 1])

func test_bfs_on_empty_dungeon_returns_empty():
	var d := Dungeon.new()
	# No start_id set -> -1. BFS should bail.
	assert_eq(d.bfs_from_start().size(), 0)

func test_bfs_handles_disconnected_warning():
	# Sanity check: if we manually break connectivity, BFS returns fewer
	# than total. This is a guardrail on the test_every_room_reachable
	# assertion above (so it isn't trivially passing).
	var d := Dungeon.new()
	d.add_room(Room.make(0, Room.TYPE_START))
	d.add_room(Room.make(1, Room.TYPE_STANDARD))
	d.add_room(Room.make(2, Room.TYPE_BOSS))
	d.start_id = 0
	d.boss_id = 2
	# Only connect 0 -> 1 (not 1 -> 2). BFS visits {0, 1} but not 2.
	d.rooms[0].connections.append(1)
	var visited := d.bfs_from_start()
	assert_eq(visited.size(), 2, "disconnected graph: BFS reaches 2 of 3")

func test_room_type_sequence_starts_with_start_ends_with_boss():
	# Ordering invariant: room 0 is start, last room is boss. Tests that
	# rely on `room_type_sequence()` for variance comparisons assume this
	# ordering is stable.
	var d := DungeonGenerator.generate(42)
	var seq := d.room_type_sequence()
	assert_eq(seq[0], Room.TYPE_START)
	assert_eq(seq[seq.size() - 1], Room.TYPE_BOSS)

# --- #371: per-room enemy_kinds list ---

func test_room_enemy_kinds_populated_per_type_across_seeds():
	# Standard rooms hold 1..MULTI_MAX kinds, boss exactly 1, non-combat empty.
	# Across a single large dungeon there must be both single and multi rooms.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		var saw_single := false
		var saw_multi := false
		for r in d.rooms:
			match r.type:
				Room.TYPE_START, Room.TYPE_BAR, Room.TYPE_POWERUP:
					assert_eq(r.enemy_kinds.size(), 0,
						"seed %d: %s room enemy_kinds should be empty" % [s, r.type])
				Room.TYPE_BOSS:
					assert_eq(r.enemy_kinds.size(), 1,
						"seed %d: boss enemy_kinds should be exactly 1" % s)
				Room.TYPE_STANDARD:
					var n: int = r.enemy_kinds.size()
					assert_between(n, 1, RoomPopulationPlanner.MULTI_MAX,
						"seed %d: standard room %d kinds out of range" % [s, r.id])
					for k in r.enemy_kinds:
						assert_true(DungeonGenerator.STANDARD_ENEMY_KINDS.has(k),
							"seed %d: standard kind %s in roster" % [s, k])
					if n == 1:
						saw_single = true
					elif n >= 2:
						saw_multi = true
		assert_true(saw_single, "seed %d: at least one single-mob standard room" % s)
		assert_true(saw_multi, "seed %d: at least one multi-mob standard room" % s)

# Strong fingerprint of a dungeon for collision tests. Captures size, type
# sequence, all connections, and enemy ids — the chance of two unseeded
# runs colliding on this is vanishingly small.
func _fingerprint(d: Dungeon) -> String:
	var parts: Array = [str(d.size())]
	for r in d.rooms:
		parts.append("%d:%s:%d:%s:%s" % [
			r.id, r.type, r.enemy_kind, r.power_up_type, str(r.connections),
		])
	return "|".join(parts)
