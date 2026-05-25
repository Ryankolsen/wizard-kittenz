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

func test_painted_tileset_has_physics_layer():
	# Issue #263: enemies need to collide with wall tiles, which requires the
	# TileSet to declare at least one physics layer. The painter has historically
	# built a no-physics TileSet — this test locks the new contract in.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)
	assert_gt(tilemap.tile_set.get_physics_layers_count(), 0,
		"painted TileSet must declare at least one physics layer")


func test_wall_tile_has_collision_polygon_on_walls_bit():
	# Issue #263: the SOURCE_WALL tile carries a square collision polygon on
	# the dedicated walls physics layer. Verifies both the polygon attachment
	# and that the layer's collision_layer bit matches the named walls bit so
	# enemy collision_mask wiring agrees with the painter.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)
	var ts: TileSet = tilemap.tile_set
	assert_eq(ts.get_physics_layer_collision_layer(0),
		EnemyBehavior.WALL_COLLISION_MASK,
		"physics layer 0 must use the named walls bit")
	var wall_src := ts.get_source(DungeonTilemapPainter.SOURCE_WALL) as TileSetAtlasSource
	assert_not_null(wall_src, "SOURCE_WALL atlas source must exist")
	var data: TileData = wall_src.get_tile_data(Vector2i(0, 0), 0)
	assert_not_null(data, "SOURCE_WALL tile data must exist")
	assert_gt(data.get_collision_polygons_count(0), 0,
		"SOURCE_WALL must carry at least one collision polygon on the walls layer")
	var points: PackedVector2Array = data.get_collision_polygon_points(0, 0)
	assert_gt(points.size(), 2, "collision polygon must have non-trivial points")


func test_non_wall_tiles_have_no_collision_polygon():
	# Issue #263: floor/start/boss/bar-entrance tiles are walkable — they must
	# not carry collision polygons, or enemies would jam against floor cells.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	DungeonTilemapPainter.new().paint(layout, tilemap, dungeon)
	var ts: TileSet = tilemap.tile_set
	for sid in [DungeonTilemapPainter.SOURCE_FLOOR,
			DungeonTilemapPainter.SOURCE_START,
			DungeonTilemapPainter.SOURCE_BOSS]:
		var src := ts.get_source(sid) as TileSetAtlasSource
		var data: TileData = src.get_tile_data(Vector2i(0, 0), 0)
		assert_eq(data.get_collision_polygons_count(0), 0,
			"source %d (floor variant) must not carry a collision polygon" % sid)


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
	# AC: exactly one bar doorway (NxN footprint where N = BAR_DOOR_FOOTPRINT)
	# is painted per dungeon, regardless of how many corridors connect to the
	# bar room. Other corridor mouths remain plain walkable floor.
	var expected: int = DungeonTilemapPainter.BAR_DOOR_FOOTPRINT * DungeonTilemapPainter.BAR_DOOR_FOOTPRINT
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var dungeon := DungeonGenerator.generate(s)
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		var tilemap := TileMap.new()
		add_child_autofree(tilemap)
		var painter := DungeonTilemapPainter.new()
		painter.paint(layout, tilemap, dungeon)
		assert_eq(painter.bar_entrance_tiles.size(), expected,
			"seed %d painted %d entrance tiles (expected %d = single NxN door)" % [s, painter.bar_entrance_tiles.size(), expected])

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
	# AC: the 2x2 door footprint sits at the bar's perimeter — two cells along
	# the outer edge plus two extending one tile inward. All four cells lie
	# inside the bar room's tile footprint (i.e. on walkable bar floor, not in
	# the surrounding wall ring). At least one cell is on the literal outer
	# edge — confirms the door sits at the corridor mouth, not floating in the
	# room interior.
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
	var any_on_edge: bool = false
	for cell in painter.bar_entrance_tiles:
		var inside: bool = cell.x >= origin.x and cell.x <= max_x and cell.y >= origin.y and cell.y <= max_y
		assert_true(inside,
			"entrance cell %s must lie inside bar room footprint [%s, %s]" % [str(cell), str(origin), str(Vector2i(max_x, max_y))])
		if cell.x == origin.x or cell.x == max_x or cell.y == origin.y or cell.y == max_y:
			any_on_edge = true
	assert_true(any_on_edge,
		"at least one door cell must sit on the bar room's outer edge")

func test_bar_entrance_footprint_is_contiguous_rectangle():
	# AC: door cells form a contiguous rectangle (no gaps, no L-shape) and span
	# at least 2x2. Lets #187's transition trigger treat bar_entrance_tiles as a
	# single rectangular zone.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	var painter := DungeonTilemapPainter.new()
	painter.paint(layout, tilemap, dungeon)

	var cells: Array = painter.bar_entrance_tiles
	var n: int = DungeonTilemapPainter.BAR_DOOR_FOOTPRINT
	assert_eq(cells.size(), n * n, "door footprint is %dx%d tiles" % [n, n])
	var xs: Array = cells.map(func(c): return c.x)
	var ys: Array = cells.map(func(c): return c.y)
	var width: int = xs.max() - xs.min() + 1
	var height: int = ys.max() - ys.min() + 1
	assert_eq(cells.size(), width * height,
		"door cells form a contiguous rectangle (%d cells, %dx%d bounding box)" % [cells.size(), width, height])
	assert_eq(width, n, "door bounding box width matches BAR_DOOR_FOOTPRINT")
	assert_eq(height, n, "door bounding box height matches BAR_DOOR_FOOTPRINT")

func test_bar_entrance_cells_are_walkable_floor_sources():
	# AC: every door cell paints either the bar-entrance source or remains on
	# walkable floor — never a solid wall. Guarantees the doorway is walkable.
	for s in [1, 2, 3, 7, 42, 123, 9999]:
		var dungeon := DungeonGenerator.generate(s)
		var layout := DungeonLayoutEngine.new().compute(dungeon)
		var tilemap := TileMap.new()
		add_child_autofree(tilemap)
		var painter := DungeonTilemapPainter.new()
		painter.paint(layout, tilemap, dungeon)
		for cell in painter.bar_entrance_tiles:
			var source_id: int = tilemap.get_cell_source_id(0, cell)
			assert_ne(source_id, DungeonTilemapPainter.SOURCE_WALL,
				"seed %d door cell %s must not be a wall" % [s, str(cell)])
			assert_ne(source_id, -1,
				"seed %d door cell %s must be a painted (non-empty) tile" % [s, str(cell)])

func test_bar_entrance_cells_use_distinct_atlas_quadrants():
	# AC: the NxN door footprint maps each cell to its matching atlas quadrant
	# — so the source bar_entrance.png renders as a single contiguous door across
	# the footprint instead of tile-repeating the full image into each cell.
	var pair := _make_layout(42)
	var dungeon: Dungeon = pair[0]
	var layout: DungeonLayout = pair[1]
	var tilemap := TileMap.new()
	add_child_autofree(tilemap)
	var painter := DungeonTilemapPainter.new()
	painter.paint(layout, tilemap, dungeon)

	var cells: Array = painter.bar_entrance_tiles
	var n: int = DungeonTilemapPainter.BAR_DOOR_FOOTPRINT
	assert_eq(cells.size(), n * n, "door footprint must be %dx%d" % [n, n])
	var xs: Array = cells.map(func(c): return c.x)
	var ys: Array = cells.map(func(c): return c.y)
	var min_x: int = xs.min()
	var min_y: int = ys.min()
	var seen: Dictionary = {}
	for cell in cells:
		var coord: Vector2i = tilemap.get_cell_atlas_coords(0, cell)
		var expected := Vector2i(cell.x - min_x, cell.y - min_y)
		assert_eq(coord, expected,
			"cell %s atlas coord %s must match quadrant offset %s" % [str(cell), str(coord), str(expected)])
		seen[coord] = true
	assert_eq(seen.size(), n * n,
		"all %d atlas quadrants must be stamped exactly once" % [n * n])

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
