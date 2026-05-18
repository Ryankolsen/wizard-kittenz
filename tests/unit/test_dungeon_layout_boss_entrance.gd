extends GutTest

# Tests for DungeonLayout.boss_corridor_entrance() — the data-layer method
# that tells main_scene where to place the ExitDoor and at what rotation.
#
# The layout engine always places the boss at grid (boss_x, 0), but the
# connecting parent room can be at any grid position. The corridor between
# them is L-shaped: horizontal at parent_center.y, then vertical at
# boss_center.x. The entry wall (and therefore the door orientation) depends
# on whether the parent is on the same grid row or a different one.
#
# The +8 half-tile shift in all positions aligns the door precisely on the
# pixel centre of the 5-tile corridor span. room_center_world returns the
# tile-origin (tile * 16) not the tile-centre (tile * 16 + 8).

const ROOM_SIZE_PX  := 192  # must match DungeonLayout constants
const CORRIDOR_PX   := 80
const STEP          := 272  # ROOM_SIZE_PX + CORRIDOR_PX
const HALF_TILE     := 8    # DungeonLayout.TILE_SIZE_PX / 2

func _make_layout(boss_id: int, positions: Dictionary, corridors: Array) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.room_positions = positions
	layout.corridors = corridors
	return layout


# --- Slice 1: same grid row — pure horizontal corridor, enters from LEFT ---

func test_same_row_parent_left_returns_left_wall_position():
	# Parent at (0,0), boss at (1,0): pure horizontal corridor enters from west.
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 1: Vector2i(1, 0)},
		[[0, 1]])
	var result: Dictionary = layout.boss_corridor_entrance(1)
	# boss_origin.x = 272; door x = 272 - 8 (half-tile into corridor)
	# boss_center_y = 96 + 8 (corridor pixel centre) = 104
	assert_eq(result["position"], Vector2(264.0, 104.0),
		"west entry: door centred on wall tile and corridor y-span")

func test_same_row_parent_left_rotation_is_zero():
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 1: Vector2i(1, 0)},
		[[0, 1]])
	var result: Dictionary = layout.boss_corridor_entrance(1)
	assert_almost_eq(float(result["rotation"]), 0.0, 0.001,
		"horizontal corridor: door is a vertical slab (rotation 0)")


# --- Slice 2: same grid row — enters from RIGHT ---

func test_same_row_parent_right_returns_right_wall_position():
	# Parent at (2,0), boss at (1,0): corridor enters from east.
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 1: Vector2i(1, 0), 2: Vector2i(2, 0)},
		[[0, 2], [2, 1]])
	var result: Dictionary = layout.boss_corridor_entrance(1)
	# boss_origin.x + ROOM_SIZE_PX = 272 + 192 = 464; door x = 464 + 8
	# boss_center_y + 8 = 104
	assert_eq(result["position"], Vector2(472.0, 104.0),
		"east entry: door centred on wall tile and corridor y-span")


# --- Slice 3: parent below boss (parent.y > boss.y) — enters from BOTTOM ---

func test_parent_below_boss_returns_bottom_wall_position():
	# Boss at (2,0), parent at (1,1): parent.y > boss.y → corridor enters south wall.
	var layout := _make_layout(2,
		{0: Vector2i(0, 0), 1: Vector2i(1, 1), 2: Vector2i(2, 0)},
		[[0, 1], [1, 2]])
	var result: Dictionary = layout.boss_corridor_entrance(2)
	# boss_origin = (544, 0); door y = 0 + 192 + 8 = 200 (wall tile centre)
	# boss_center.x = 544 + 96 + 8 = 648
	assert_eq(result["position"], Vector2(648.0, 200.0),
		"south entry: door centred on wall tile and corridor x-span")

func test_parent_below_boss_rotation_is_half_pi():
	var layout := _make_layout(2,
		{0: Vector2i(0, 0), 1: Vector2i(1, 1), 2: Vector2i(2, 0)},
		[[0, 1], [1, 2]])
	var result: Dictionary = layout.boss_corridor_entrance(2)
	assert_almost_eq(float(result["rotation"]), PI / 2.0, 0.001,
		"vertical corridor: door is a horizontal slab (rotation PI/2)")


# --- Slice 4: parent above boss (parent.y < boss.y) — enters from TOP ---

func test_parent_above_boss_returns_top_wall_position():
	# Boss at (2,0), parent at (1,-1): parent.y < boss.y → enters north wall.
	var layout := _make_layout(2,
		{0: Vector2i(0, 0), 1: Vector2i(1, -1), 2: Vector2i(2, 0)},
		[[0, 1], [1, 2]])
	var result: Dictionary = layout.boss_corridor_entrance(2)
	# boss_origin.y = 0; door y = 0 - 8 = -8 (wall tile centre above boss room)
	# boss_center.x = 544 + 96 + 8 = 648
	assert_eq(result["position"], Vector2(648.0, -8.0),
		"north entry: door centred on wall tile above boss room")


# --- Slice 5: unknown boss_id returns zero ---

func test_unknown_boss_id_returns_zero_position():
	var layout := _make_layout(99,
		{0: Vector2i(0, 0)},
		[])
	var result: Dictionary = layout.boss_corridor_entrance(99)
	assert_eq(result["position"], Vector2.ZERO)
