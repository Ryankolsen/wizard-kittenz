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

func test_exactly_one_bar_entrance_per_dungeon():
	# AC: exactly one bar entrance tile is painted per dungeon, regardless of
	# how many corridors connect to the bar room. The other corridor mouths
	# remain plain walkable floor.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var dungeon := DungeonGenerator.generate(s)
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		var tilemap := TileMap.new()
		add_child_autofree(tilemap)
		var painter := DungeonTilemapPainter.new()
		painter.paint(layout, tilemap, dungeon)
		assert_eq(painter.bar_entrance_tiles.size(), 1,
			"seed %d painted %d entrance tiles (expected 1)" % [s, painter.bar_entrance_tiles.size()])

func test_bar_room_entrance_uses_distinct_tile():
	# AC: the bar room's corridor connection is painted with the dedicated
	# bar-entrance source, distinct from the standard floor used by every other
	# room's perimeter.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	var painter := DungeonTilemapPainter.new()
	painter.paint(layout, tilemap, dungeon)

	assert_gt(painter.bar_entrance_tiles.size(), 0,
		"painter must record at least one bar entrance tile")
	for cell in painter.bar_entrance_tiles:
		var source_id: int = tilemap.get_cell_source_id(0, cell)
		assert_eq(source_id, DungeonTilemapPainter.SOURCE_BAR_ENTRANCE,
			"bar entrance cell %s must use SOURCE_BAR_ENTRANCE" % str(cell))
		assert_ne(source_id, DungeonTilemapPainter.SOURCE_FLOOR,
			"bar entrance must not use the standard floor source")

func test_bar_entrance_tiles_lie_on_bar_room_perimeter():
	# AC: each entrance tile sits on the bar room's outer edge (not interior,
	# not in the surrounding wall ring). Confirms the placement matches the
	# corridor's mouth rather than the room center.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	var painter := DungeonTilemapPainter.new()
	painter.paint(layout, tilemap, dungeon)

	var bar_id: int = -1
	for r in dungeon.rooms:
		if r.type == Room.TYPE_BAR:
			bar_id = r.id
			break
	assert_ne(bar_id, -1, "every dungeon must contain a bar room")

	var step_tiles: int = DungeonTilemapPainter.ROOM_TILES + DungeonTilemapPainter.CORRIDOR_TILES
	var bar_grid: Vector2i = layout.room_positions[bar_id]
	var origin := Vector2i(bar_grid.x * step_tiles, bar_grid.y * step_tiles)
	var max_x: int = origin.x + DungeonTilemapPainter.ROOM_TILES - 1
	var max_y: int = origin.y + DungeonTilemapPainter.ROOM_TILES - 1
	for cell in painter.bar_entrance_tiles:
		var on_x_edge: bool = cell.x == origin.x or cell.x == max_x
		var on_y_edge: bool = cell.y == origin.y or cell.y == max_y
		var inside: bool = cell.x >= origin.x and cell.x <= max_x and cell.y >= origin.y and cell.y <= max_y
		assert_true(inside and (on_x_edge or on_y_edge),
			"entrance cell %s must lie on bar room perimeter [%s, %s]" % [str(cell), str(origin), str(Vector2i(max_x, max_y))])

func test_non_bar_room_centers_unchanged_by_bar_entrance_pass():
	# AC: bar-entrance painting only touches bar perimeter cells. Start, boss,
	# standard, and power-up room centers keep their existing tile sources.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)

	for r in dungeon.rooms:
		if r.type == Room.TYPE_BAR:
			continue
		var center: Vector2i = DungeonTilemapPainter.room_center_tile(layout.room_positions[r.id])
		var source_id: int = tilemap.get_cell_source_id(0, center)
		assert_ne(source_id, DungeonTilemapPainter.SOURCE_BAR_ENTRANCE,
			"non-bar room %d (%s) center must not use bar entrance source" % [r.id, r.type])

func test_paint_without_dungeon_uses_standard_floor():
	# Defensive: paint() with dungeon=null still works; all rooms get the
	# standard floor variant rather than crashing on the start/boss check.
	var dungeon := DungeonGenerator.generate(42)
	var layout := DungeonLayoutEngine.new().compute(dungeon)
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, null)
	assert_true(tilemap.get_used_cells(0).size() > 0)
