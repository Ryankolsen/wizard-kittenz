extends GutTest

# Tests for DungeonLayout.boss_corridor_entrance() — the data-layer method
# that tells main_scene where to place the ExitDoor and at what rotation.
#
# The layout engine guarantees the boss's parent is always at y < boss_grid.y
# (north-wall invariant), so the corridor always enters through the north wall.
# The door is always a horizontal slab (rotation PI/2) centred on the corridor
# x-span and sitting on the wall tile just above the boss room.

const ROOM_SIZE_PX  := 192  # must match DungeonLayout constants
const CORRIDOR_PX   := 80
const STEP          := 272  # ROOM_SIZE_PX + CORRIDOR_PX
const HALF_TILE     := 8    # DungeonLayout.TILE_SIZE_PX / 2

func _make_layout(boss_id: int, positions: Dictionary, corridors: Array) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.room_positions = positions
	layout.corridors = corridors
	return layout


# --- Slice 1: parent above boss — north wall position ---

func test_parent_above_boss_returns_north_wall_position():
	# Parent at (0,0), boss at (1,1): parent.y=0 < boss.y=1 → north wall entry.
	# boss_origin = (272, 272); door y = 272 - 8 = 264
	# boss_center.x = 272 + 96 + 8 = 376
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 1: Vector2i(1, 1)},
		[[0, 1]])
	var result: Dictionary = layout.boss_corridor_entrance(1)
	assert_eq(result["position"], Vector2(376.0, 264.0),
		"north entry: door centred on wall tile above boss room")

func test_parent_above_boss_rotation_is_half_pi():
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 1: Vector2i(1, 1)},
		[[0, 1]])
	var result: Dictionary = layout.boss_corridor_entrance(1)
	assert_almost_eq(float(result["rotation"]), PI / 2.0, 0.001,
		"north entry: door is a horizontal slab (rotation PI/2)")


# --- Slice 2: parent at different x but still above ---

func test_parent_at_different_x_still_uses_boss_center_x():
	# Parent at (3, 0), boss at (5, 1): parent.y=0 < boss.y=1 → north wall.
	# boss_origin = (5*272, 272) = (1360, 272); door y = 264
	# boss_center.x = 1360 + 96 + 8 = 1464
	var layout := _make_layout(2,
		{0: Vector2i(0, 0), 1: Vector2i(3, 0), 2: Vector2i(5, 1)},
		[[0, 1], [1, 2]])
	var result: Dictionary = layout.boss_corridor_entrance(2)
	assert_eq(result["position"], Vector2(1464.0, 264.0),
		"north entry x is centred on boss room regardless of parent x")


# --- Slice 3: unknown boss_id returns zero ---

func test_unknown_boss_id_returns_zero_position():
	var layout := _make_layout(99,
		{0: Vector2i(0, 0)},
		[])
	var result: Dictionary = layout.boss_corridor_entrance(99)
	assert_eq(result["position"], Vector2.ZERO)
