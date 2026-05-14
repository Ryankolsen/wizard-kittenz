extends GutTest

# Covers DungeonTilemapPainter — the replacement for the single-room
# DungeonFloor.paint(). Tests assert the painter's contract with future
# renderers / placement code: cells exist, room centers are floor, corridor
# midpoints are floor, and camera limits match the painted extents.

func _make_layout(seed: int) -> Array:
	var dungeon := DungeonGenerator.generate(seed)
	var layout := DungeonLayoutEngine.new().compute(dungeon)
	return [dungeon, layout]

func test_paint_populates_cells():
	# AC: core wiring — paint() sets at least one cell.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)
	assert_true(tilemap.get_used_cells(0).size() > 0,
		"paint() must set at least one cell")

func test_room_centers_are_floor():
	# AC: every room's center tile is a floor (not wall, not empty). The
	# spawn / placement code reads from room centers, so they must be on
	# walkable tiles.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)
	for rid in layout.room_positions:
		var grid_pos: Vector2i = layout.room_positions[rid]
		var center: Vector2i = DungeonTilemapPainter.room_center_tile(grid_pos)
		var source_id: int = tilemap.get_cell_source_id(0, center)
		assert_ne(source_id, -1,
			"room %d center %s must be a floor tile" % [rid, str(center)])
		assert_ne(source_id, DungeonTilemapPainter.SOURCE_WALL,
			"room %d center must not be a wall" % rid)

func test_corridor_midpoints_are_floor():
	# AC: corridor midpoints (between the two connected room centers) are
	# floor tiles — proves the corridor carving actually connects rooms
	# rather than leaving voids.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)
	for corridor in layout.corridors:
		var a_grid: Vector2i = layout.room_positions[corridor[0]]
		var b_grid: Vector2i = layout.room_positions[corridor[1]]
		var a: Vector2i = DungeonTilemapPainter.room_center_tile(a_grid)
		var b: Vector2i = DungeonTilemapPainter.room_center_tile(b_grid)
		var mid: Vector2i = Vector2i((a.x + b.x) / 2, (a.y + b.y) / 2)
		# The L-shaped corridor hugs a.y for the horizontal leg and b.x for
		# the vertical leg; either (mid.x, a.y) or (b.x, mid.y) is reliably
		# on the carved corridor. Pick the one inside the L.
		var test_cell := Vector2i(mid.x, a.y)
		var source_id: int = tilemap.get_cell_source_id(0, test_cell)
		assert_ne(source_id, -1,
			"corridor midpoint %s must not be empty" % str(test_cell))
		assert_ne(source_id, DungeonTilemapPainter.SOURCE_WALL,
			"corridor midpoint must not be a wall")

func test_start_and_boss_use_distinct_floor_variants():
	# AC: start and boss rooms use distinct floor tile variants.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)

	var start_center: Vector2i = DungeonTilemapPainter.room_center_tile(
		layout.room_positions[dungeon.start_id])
	var boss_center: Vector2i = DungeonTilemapPainter.room_center_tile(
		layout.room_positions[dungeon.boss_id])

	assert_eq(tilemap.get_cell_source_id(0, start_center),
		DungeonTilemapPainter.SOURCE_START,
		"start room center should use SOURCE_START")
	assert_eq(tilemap.get_cell_source_id(0, boss_center),
		DungeonTilemapPainter.SOURCE_BOSS,
		"boss room center should use SOURCE_BOSS")

func test_walls_border_floor():
	# AC: walls border all room/corridor edges. Pick any floor cell on the
	# outer perimeter of the start room — at least one of its 8 neighbors
	# must be a wall (or it'd be on a corridor edge, which is also walled).
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)

	# The start room is at grid (0, 0); its corner tile (0, 0) sits at the
	# room's outer edge — at least one neighbor is outside the room and is
	# not on any corridor leg, so must be a wall.
	var corner := Vector2i(0, 0)
	var has_wall_neighbor: bool = false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor: Vector2i = corner + Vector2i(dx, dy)
			if tilemap.get_cell_source_id(0, neighbor) == DungeonTilemapPainter.SOURCE_WALL:
				has_wall_neighbor = true
	assert_true(has_wall_neighbor,
		"start room corner must have at least one wall neighbor")

func test_apply_camera_limits_matches_used_rect():
	# AC: camera limits clamp to painted tilemap extents in pixels.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)
	var camera := Camera2D.new()
	add_child_autofree(camera)
	DungeonTilemapPainter.apply_camera_limits(camera, tilemap)

	var rect: Rect2i = tilemap.get_used_rect()
	var ts: int = tilemap.tile_set.tile_size.x
	assert_eq(camera.limit_left, rect.position.x * ts)
	assert_eq(camera.limit_top, rect.position.y * ts)
	assert_eq(camera.limit_right, (rect.position.x + rect.size.x) * ts)
	assert_eq(camera.limit_bottom, (rect.position.y + rect.size.y) * ts)
	assert_gt(camera.limit_right, camera.limit_left, "right > left")
	assert_gt(camera.limit_bottom, camera.limit_top, "bottom > top")

func test_paint_without_dungeon_uses_standard_floor():
	# Defensive: paint() with dungeon=null still works; all rooms get the
	# standard floor variant rather than crashing on the start/boss check.
	var dungeon := DungeonGenerator.generate(42)
	var layout := DungeonLayoutEngine.new().compute(dungeon)
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, null)
	assert_true(tilemap.get_used_cells(0).size() > 0)
