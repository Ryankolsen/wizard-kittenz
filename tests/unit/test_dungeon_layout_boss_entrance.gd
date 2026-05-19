extends GutTest

# Tests for DungeonLayout.boss_exit_position() — the data-layer method that
# tells main_scene where to place the ExitDoor on the boss room's south wall.
#
# Design: the corridor always enters the boss room from the north (layout engine
# invariant: parent.y < boss.y). The exit door is on the SOUTH wall so the
# player enters freely, kills the boss, then the south door unlocks and they
# exit to the next level.
#
# South wall position: y = boss_origin.y + ROOM_SIZE_PX - TILE_SIZE_PX/2
#   = boss_origin.y + 192 - 8 = boss_origin.y + 184
# x: centred on the boss room, same formula as corridor_center_x.

const ROOM_SIZE_PX  := 192  # must match DungeonLayout constants
const CORRIDOR_PX   := 80
const STEP          := 272  # ROOM_SIZE_PX + CORRIDOR_PX
const HALF_TILE     := 8    # DungeonLayout.TILE_SIZE_PX / 2

func _make_layout(boss_id: int, positions: Dictionary, corridors: Array) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.room_positions = positions
	layout.corridors = corridors
	return layout


# --- Slice 1: south wall position ---

func test_returns_south_wall_position():
	# Parent at (0,0), boss at (1,1).
	# boss_origin = (272, 272); door y = 272 + 192 - 8 = 456
	# room_center_x = 272 + 96 + 8 = 376
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 1: Vector2i(1, 1)},
		[[0, 1]])
	var result: Dictionary = layout.boss_exit_position(1)
	assert_eq(result["position"], Vector2(376.0, 456.0),
		"south wall: door on last tile row of boss room")

func test_rotation_is_half_pi():
	var layout := _make_layout(1,
		{0: Vector2i(0, 0), 1: Vector2i(1, 1)},
		[[0, 1]])
	var result: Dictionary = layout.boss_exit_position(1)
	assert_almost_eq(float(result["rotation"]), PI / 2.0, 0.001,
		"south wall: door is a horizontal slab (rotation PI/2)")


# --- Slice 2: x is centred on the boss room regardless of parent x ---

func test_x_uses_boss_room_center():
	# Parent at (3,0), boss at (5,1).
	# boss_origin = (1360, 272); y = 272 + 192 - 8 = 456
	# room_center_x = 1360 + 96 + 8 = 1464
	var layout := _make_layout(2,
		{0: Vector2i(0, 0), 1: Vector2i(3, 0), 2: Vector2i(5, 1)},
		[[0, 1], [1, 2]])
	var result: Dictionary = layout.boss_exit_position(2)
	assert_eq(result["position"], Vector2(1464.0, 456.0),
		"south wall x is centred on boss room regardless of parent x")


# --- Slice 3: unknown boss_id returns zero ---

func test_unknown_boss_id_returns_zero_position():
	var layout := _make_layout(99,
		{0: Vector2i(0, 0)},
		[])
	var result: Dictionary = layout.boss_exit_position(99)
	assert_eq(result["position"], Vector2.ZERO)
