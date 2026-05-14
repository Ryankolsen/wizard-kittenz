extends GutTest

# --- Issue tests (6 acceptance scenarios) ---

func test_compute_returns_layout_with_position_per_room():
	# Issue test 1: compute() returns a non-null DungeonLayout with one
	# position entry per room in the dungeon.
	var dungeon := DungeonGenerator.generate(42)
	var layout := DungeonLayoutEngine.new().compute(dungeon)
	assert_not_null(layout, "compute() returns a layout")
	assert_eq(layout.room_positions.size(), dungeon.rooms.size(),
		"one grid position per room")

func test_start_room_is_at_origin():
	# Issue test 2: start room is always at Vector2i(0, 0).
	for s in [1, 2, 3, 7, 42]:
		var dungeon := DungeonGenerator.generate(s)
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		assert_eq(layout.room_positions[dungeon.start_id], Vector2i(0, 0),
			"seed %d: start room at origin" % s)

func test_no_position_collisions():
	# Issue test 3: every room has a unique grid position.
	for s in [1, 2, 3, 7, 42, 123]:
		var dungeon := DungeonGenerator.generate(s)
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		var positions: Array = layout.room_positions.values()
		var unique: Dictionary = {}
		for p in positions:
			unique[p] = true
		assert_eq(unique.size(), positions.size(),
			"seed %d: %d / %d positions unique" % [s, unique.size(), positions.size()])

func test_corridor_coverage():
	# Issue test 4: every directed edge in the dungeon graph appears as a
	# corridor entry in the layout.
	var dungeon := DungeonGenerator.generate(42)
	var layout := DungeonLayoutEngine.new().compute(dungeon)
	for room in dungeon.rooms:
		for connected_id in room.connections:
			assert_true(layout.corridors.has([room.id, connected_id]),
				"corridor [%d -> %d] present" % [room.id, connected_id])

func test_compute_is_deterministic():
	# Issue test 5: same dungeon -> identical layouts across two calls.
	var dungeon := DungeonGenerator.generate(42)
	var layout_a := DungeonLayoutEngine.new().compute(dungeon)
	var layout_b := DungeonLayoutEngine.new().compute(dungeon)
	assert_eq(layout_a.room_positions, layout_b.room_positions,
		"room_positions identical across calls")
	assert_eq(layout_a.corridors, layout_b.corridors,
		"corridors identical across calls")

func test_minimal_dungeon_two_rooms_one_edge():
	# Issue test 6: minimal dungeon with only start + boss produces a
	# 2-position layout with 1 corridor. The real DungeonGenerator never
	# emits a 2-room dungeon (MIN_ROOMS = 5), so we construct one manually.
	var dungeon := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var boss := Room.make(1, Room.TYPE_BOSS)
	start.connections.append(1)
	dungeon.add_room(start)
	dungeon.add_room(boss)
	dungeon.start_id = 0
	dungeon.boss_id = 1
	var layout := DungeonLayoutEngine.new().compute(dungeon)
	assert_eq(layout.room_positions.size(), 2, "2 positions placed")
	assert_eq(layout.corridors.size(), 1, "1 corridor entry")
	assert_eq(layout.corridors[0], [0, 1], "corridor is start -> boss")

# --- Coverage beyond the 6 issue scenarios ---

func test_boss_is_at_furthest_grid_distance():
	# Acceptance criterion: boss is placed at the furthest manhattan distance
	# from the start room. The generator picks the boss's parent randomly,
	# so the boss is not always the deepest tree node — the layout engine
	# must enforce this independently of the graph shape.
	for s in [1, 2, 3, 7, 42, 100, 123, 9999]:
		var dungeon := DungeonGenerator.generate(s)
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		var boss_pos: Vector2i = layout.room_positions[dungeon.boss_id]
		var boss_dist: int = abs(boss_pos.x) + abs(boss_pos.y)
		for rid in layout.room_positions:
			if rid == dungeon.boss_id:
				continue
			var p: Vector2i = layout.room_positions[rid]
			var d: int = abs(p.x) + abs(p.y)
			assert_true(boss_dist > d,
				"seed %d: boss dist %d not strictly greater than room %d dist %d"
				% [s, boss_dist, rid, d])

func test_grid_to_world_uses_room_size_plus_corridor_width():
	# DungeonLayout.grid_to_world is a tiny pure helper, but the renderer
	# depends on it placing rooms one (room_size + corridor_width) step
	# apart in each axis. Lock the contract.
	var layout := DungeonLayout.new()
	var world := layout.grid_to_world(Vector2i(2, 3), 64, 16)
	assert_eq(world, Vector2(160, 240), "grid_to_world((2,3), 64, 16) = (160, 240)")

func test_corridors_count_matches_edge_count():
	# Total corridors == total directed edges in the dungeon. Tree dungeon
	# with N rooms has N-1 edges; verify the count matches so we can't
	# silently lose or duplicate corridors.
	for s in [1, 2, 3, 7, 42]:
		var dungeon := DungeonGenerator.generate(s)
		var edge_count := 0
		for r in dungeon.rooms:
			edge_count += r.connections.size()
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		assert_eq(layout.corridors.size(), edge_count,
			"seed %d: corridor count matches edge count" % s)
