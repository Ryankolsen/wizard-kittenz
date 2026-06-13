extends GutTest

# Tests for BossCorridorLocator — pure module returning the world-pixel
# position of the pre-boss healing box on the boss room's incoming corridor.

const STEP_PX: int = 272  # DungeonLayout.ROOM_SIZE_PX(192) + CORRIDOR_WIDTH_PX(80)
const ROOM_PX: int = 192
const HALF_TILE: float = 8.0  # DungeonLayout.TILE_SIZE_PX / 2

func _make_layout(boss_id: int, positions: Dictionary, corridors: Array) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.room_positions = positions
	layout.corridors = corridors
	layout.boss_id = boss_id
	return layout

func _make_minimal_dungeon(parent_grid: Vector2i, boss_grid: Vector2i) -> Array:
	var dungeon := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var boss := Room.make(1, Room.TYPE_BOSS)
	start.connections.append(1)
	dungeon.add_room(start)
	dungeon.add_room(boss)
	dungeon.start_id = 0
	dungeon.boss_id = 1
	var layout := _make_layout(1,
		{0: parent_grid, 1: boss_grid},
		[[0, 1]])
	return [dungeon, layout]


# --- Core wiring ---

func test_returns_non_zero_vector_for_valid_input():
	var pair := _make_minimal_dungeon(Vector2i(0, 0), Vector2i(0, 1))
	var pos: Vector2 = BossCorridorLocator.locate(pair[0], pair[1])
	assert_ne(pos, Vector2.ZERO, "locator returns a real position for a valid boss corridor")


# --- Lies on the boss's incoming corridor ---

func test_x_aligns_with_boss_corridor_column():
	# Boss at grid (2, 3); painter draws the vertical corridor leg at the
	# standard ROOM_TILES/2 column of the boss cell, so x = 2*272 + 96 + 8 = 648.
	var pair := _make_minimal_dungeon(Vector2i(2, 2), Vector2i(2, 3))
	var pos: Vector2 = BossCorridorLocator.locate(pair[0], pair[1])
	assert_almost_eq(pos.x, 2.0 * STEP_PX + ROOM_PX / 2.0 + HALF_TILE, 0.001,
		"x matches the painter's corridor column for the boss cell")

func test_y_is_between_parent_south_and_boss_north():
	# Parent at (0,0), boss at (0,1). parent_south = 192, boss_north = 272.
	# Midpoint = 232 — sits inside the corridor strip.
	var pair := _make_minimal_dungeon(Vector2i(0, 0), Vector2i(0, 1))
	var pos: Vector2 = BossCorridorLocator.locate(pair[0], pair[1])
	var parent_south: float = 0.0 * STEP_PX + ROOM_PX
	var boss_north: float = 1.0 * STEP_PX
	assert_true(pos.y > parent_south and pos.y < boss_north,
		"y %f lies strictly between parent south %f and boss north %f"
		% [pos.y, parent_south, boss_north])

func test_cross_check_against_corridor_edge_in_layout():
	# The [parent, boss_id] edge must exist in layout.corridors and the returned
	# point must use the parent at that edge — not some other graph neighbor.
	var dungeon := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var mid := Room.make(2, Room.TYPE_STANDARD)
	var boss := Room.make(1, Room.TYPE_BOSS)
	start.connections.append(2)
	mid.connections.append(1)
	dungeon.add_room(start)
	dungeon.add_room(mid)
	dungeon.add_room(boss)
	dungeon.start_id = 0
	dungeon.boss_id = 1
	# mid is the boss's parent; corridor [2, 1] is the boss's incoming edge.
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 2: Vector2i(0, 1), 1: Vector2i(0, 2)},
		[[0, 2], [2, 1]])
	var pos: Vector2 = BossCorridorLocator.locate(dungeon, layout)
	# parent_south = 1*272 + 192 = 464; boss_north = 2*272 = 544; midpoint = 504.
	assert_almost_eq(pos.y, 504.0, 0.001,
		"y uses parent (mid) at grid (0,1), not start at (0,0)")


# --- Real generated layout ---

func test_real_dungeon_position_is_inside_corridor():
	# Across several seeds, the returned point must sit between the boss room's
	# parent south wall and the boss room's north wall on the corridor column.
	for s in [1, 2, 3, 7, 42, 123]:
		var dungeon := DungeonGenerator.generate(s)
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		var pos: Vector2 = BossCorridorLocator.locate(dungeon, layout)
		var boss_grid: Vector2i = layout.room_positions[dungeon.boss_id]
		var parent_id: int = -1
		for pair in layout.corridors:
			if pair[1] == dungeon.boss_id:
				parent_id = pair[0]
				break
		var parent_grid: Vector2i = layout.room_positions[parent_id]
		var parent_south: float = float(parent_grid.y) * STEP_PX + ROOM_PX
		var boss_north: float = float(boss_grid.y) * STEP_PX
		var expected_x: float = float(boss_grid.x) * STEP_PX + ROOM_PX / 2.0 + HALF_TILE
		assert_almost_eq(pos.x, expected_x, 0.001,
			"seed %d: x on boss corridor column" % s)
		assert_true(pos.y > parent_south and pos.y < boss_north,
			"seed %d: y %f between parent_south %f and boss_north %f"
			% [s, pos.y, parent_south, boss_north])


# --- Determinism ---

func test_deterministic_on_repeat_calls():
	var dungeon := DungeonGenerator.generate(42)
	var layout := DungeonLayoutEngine.new().compute(dungeon)
	var a: Vector2 = BossCorridorLocator.locate(dungeon, layout)
	var b: Vector2 = BossCorridorLocator.locate(dungeon, layout)
	assert_eq(a, b, "same inputs yield the same position")


# --- Edge cases ---

func test_null_dungeon_returns_zero():
	var layout := _make_layout(-1, {}, [])
	assert_eq(BossCorridorLocator.locate(null, layout), Vector2.ZERO)

func test_null_layout_returns_zero():
	var dungeon := Dungeon.new()
	assert_eq(BossCorridorLocator.locate(dungeon, null), Vector2.ZERO)

func test_missing_boss_returns_zero():
	var dungeon := Dungeon.new()
	dungeon.boss_id = -1
	var layout := _make_layout(-1, {0: Vector2i(0, 0)}, [])
	assert_eq(BossCorridorLocator.locate(dungeon, layout), Vector2.ZERO)

func test_boss_with_no_incoming_edge_returns_zero():
	var dungeon := Dungeon.new()
	var boss := Room.make(1, Room.TYPE_BOSS)
	dungeon.add_room(boss)
	dungeon.boss_id = 1
	var layout := _make_layout(1, {1: Vector2i(0, 0)}, [])
	assert_eq(BossCorridorLocator.locate(dungeon, layout), Vector2.ZERO,
		"no incoming corridor edge -> zero sentinel")
