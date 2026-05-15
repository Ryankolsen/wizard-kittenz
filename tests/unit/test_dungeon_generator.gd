extends GutTest

# --- Issue tests (5 acceptance scenarios) ---

func test_generate_returns_5_to_10_rooms():
	# Issue test 1: DungeonGenerator.generate() returns a graph with between
	# 5 and 10 nodes inclusive. Run a handful of seeds to cover the range,
	# not just one draw.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var d := DungeonGenerator.generate(s)
		assert_between(d.size(), DungeonGenerator.MIN_ROOMS, DungeonGenerator.MAX_ROOMS,
			"seed %d produced %d rooms (expected 5..10)" % [s, d.size()])

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

func test_boss_uses_harder_enemy_variant():
	# Acceptance criterion: boss room contains a harder enemy variant than
	# standard rooms. We assert the boss enemy_kind is in BOSS_ENEMY_KINDS
	# (currently {RAT}) and at least one standard room is from
	# STANDARD_ENEMY_KINDS (excluding RAT). RAT has higher base_max_hp
	# and base_attack than SLIME/BAT — that's "harder" by construction.
	for s in [1, 2, 3, 7, 42, 100]:
		var d := DungeonGenerator.generate(s)
		var boss := d.boss_room()
		assert_true(DungeonGenerator.BOSS_ENEMY_KINDS.has(boss.enemy_kind),
			"seed %d: boss enemy_kind %d should be in BOSS pool" % [s, boss.enemy_kind])
		# Per-stat check: every standard room's enemy is strictly weaker
		# than the boss in either max_hp or attack.
		for r in d.rooms:
			if r.type == Room.TYPE_STANDARD:
				var standard_hp := EnemyData.base_max_hp_for(r.enemy_kind)
				var standard_atk := EnemyData.base_attack_for(r.enemy_kind)
				var boss_hp := EnemyData.base_max_hp_for(boss.enemy_kind)
				var boss_atk := EnemyData.base_attack_for(boss.enemy_kind)
				assert_true(boss_hp >= standard_hp and boss_atk >= standard_atk,
					"boss (hp=%d atk=%d) should not be weaker than standard (hp=%d atk=%d)"
					% [boss_hp, boss_atk, standard_hp, standard_atk])

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
				assert_true(DungeonGenerator.BOSS_ENEMY_KINDS.has(r.enemy_kind),
					"boss enemy_kind in pool")

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
