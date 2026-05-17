class_name DungeonTilemapPainter
extends RefCounted

# Paints a DungeonLayout onto a TileMap: room floors, connecting corridors,
# and surrounding walls. Replaces the old single-room DungeonFloor.paint().
# No knowledge of enemies, doors, or players — pure layout-to-tiles.
#
# Tile variants (atlas sources): standard floor, start-room floor (cool tint),
# boss-room floor (warm tint), wall. Each source uses the existing floor.png
# texture with per-source color multiplication baked in at TileSet build time
# — Godot's TileMap can't modulate individual cells, so distinct tints have
# to live in separate atlas sources.
#
# Corridor geometry: L-shape between room centers — horizontal segment at
# the source room's y, then vertical at the destination's x — CORRIDOR_TILES
# thick. The layout engine guarantees each corridor edge mirrors a graph
# edge, so painting all corridors yields a fully connected floor region.

const FLOOR_TEXTURE_PATH := "res://assets/sprites/floor.png"
const TILE_SIZE := 16
const ROOM_TILES := 12
const CORRIDOR_TILES := 5

const SOURCE_FLOOR := 0
const SOURCE_START := 1
const SOURCE_BOSS := 2
const SOURCE_WALL := 3

# Paints the layout onto `tilemap`. If `dungeon` is provided, the start and
# boss rooms receive distinct floor variants; otherwise every room gets the
# standard floor (used by tests that don't care about variants).
func paint(layout: DungeonLayout, tilemap: TileMap, dungeon: Dungeon = null) -> void:
	if layout == null or tilemap == null:
		return
	tilemap.tile_set = _build_tileset()

	var start_id: int = -1
	var boss_id: int = -1
	if dungeon != null:
		start_id = dungeon.start_id
		boss_id = dungeon.boss_id

	var floor_cells: Dictionary = {}
	var step_tiles: int = ROOM_TILES + CORRIDOR_TILES

	for rid in layout.room_positions:
		var grid_pos: Vector2i = layout.room_positions[rid]
		var origin := Vector2i(grid_pos.x * step_tiles, grid_pos.y * step_tiles)
		var src: int = SOURCE_FLOOR
		if rid == start_id:
			src = SOURCE_START
		elif rid == boss_id:
			src = SOURCE_BOSS
		for y in range(ROOM_TILES):
			for x in range(ROOM_TILES):
				var cell := origin + Vector2i(x, y)
				tilemap.set_cell(0, cell, src, Vector2i(0, 0))
				floor_cells[cell] = true

	# Carve corridors between connected rooms. floor_cells is updated so the
	# wall pass treats corridor tiles as floor (no walls inside corridors).
	for pair in layout.corridors:
		var a: Vector2i = layout.room_positions[pair[0]]
		var b: Vector2i = layout.room_positions[pair[1]]
		_paint_corridor(tilemap, a, b, step_tiles, floor_cells)

	# Re-stamp start and boss room interiors after corridors: corridor legs
	# pass through room centers using the standard floor source, which would
	# otherwise overwrite the distinct start/boss variants inside the room.
	_repaint_variant_room(tilemap, layout, start_id, SOURCE_START)
	_repaint_variant_room(tilemap, layout, boss_id, SOURCE_BOSS)

	_paint_walls(tilemap, floor_cells)

func _repaint_variant_room(tilemap: TileMap, layout: DungeonLayout, rid: int, source_id: int) -> void:
	if rid < 0 or not layout.room_positions.has(rid):
		return
	var step_tiles: int = ROOM_TILES + CORRIDOR_TILES
	var grid_pos: Vector2i = layout.room_positions[rid]
	var origin := Vector2i(grid_pos.x * step_tiles, grid_pos.y * step_tiles)
	for y in range(ROOM_TILES):
		for x in range(ROOM_TILES):
			tilemap.set_cell(0, origin + Vector2i(x, y), source_id, Vector2i(0, 0))

# Returns the tile-space center of a room — useful to placement code (exit
# door, player spawn) that consumes the painter's output.
static func room_center_tile(grid_pos: Vector2i) -> Vector2i:
	var step_tiles: int = ROOM_TILES + CORRIDOR_TILES
	return Vector2i(
		grid_pos.x * step_tiles + ROOM_TILES / 2,
		grid_pos.y * step_tiles + ROOM_TILES / 2,
	)

# Clamps `camera` to the pixel extents of `tilemap.get_used_rect()`. The
# rect is in tile coords; convert via tile_set.tile_size (falls back to
# TILE_SIZE if no tile_set is set).
static func apply_camera_limits(camera: Camera2D, tilemap: TileMap) -> void:
	if camera == null or tilemap == null:
		return
	var rect: Rect2i = tilemap.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return
	var ts: int = TILE_SIZE
	if tilemap.tile_set != null:
		ts = tilemap.tile_set.tile_size.x
	camera.limit_left = rect.position.x * ts
	camera.limit_top = rect.position.y * ts
	camera.limit_right = (rect.position.x + rect.size.x) * ts
	camera.limit_bottom = (rect.position.y + rect.size.y) * ts

func _paint_corridor(tilemap: TileMap, a_grid: Vector2i, b_grid: Vector2i, step_tiles: int, floor_cells: Dictionary) -> void:
	var a_center := Vector2i(a_grid.x * step_tiles + ROOM_TILES / 2, a_grid.y * step_tiles + ROOM_TILES / 2)
	var b_center := Vector2i(b_grid.x * step_tiles + ROOM_TILES / 2, b_grid.y * step_tiles + ROOM_TILES / 2)
	var half: int = CORRIDOR_TILES / 2
	# Horizontal leg at a_center.y from min(a.x, b.x) to max(a.x, b.x).
	var x0: int = min(a_center.x, b_center.x)
	var x1: int = max(a_center.x, b_center.x)
	for x in range(x0, x1 + 1):
		for dy in range(-half, half + 1):
			var cell := Vector2i(x, a_center.y + dy)
			tilemap.set_cell(0, cell, SOURCE_FLOOR, Vector2i(0, 0))
			floor_cells[cell] = true
	# Vertical leg at b_center.x from min(a.y, b.y) to max(a.y, b.y).
	var y0: int = min(a_center.y, b_center.y)
	var y1: int = max(a_center.y, b_center.y)
	for y in range(y0, y1 + 1):
		for dx in range(-half, half + 1):
			var cell := Vector2i(b_center.x + dx, y)
			tilemap.set_cell(0, cell, SOURCE_FLOOR, Vector2i(0, 0))
			floor_cells[cell] = true

func _paint_walls(tilemap: TileMap, floor_cells: Dictionary) -> void:
	var wall_cells: Dictionary = {}
	for cell in floor_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var neighbor: Vector2i = cell + Vector2i(dx, dy)
				if not floor_cells.has(neighbor):
					wall_cells[neighbor] = true
	for cell in wall_cells:
		tilemap.set_cell(0, cell, SOURCE_WALL, Vector2i(0, 0))

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	_add_tinted_source(ts, SOURCE_FLOOR, Color(1.0, 1.0, 1.0))
	_add_tinted_source(ts, SOURCE_START, Color(0.55, 0.85, 1.0))
	_add_tinted_source(ts, SOURCE_BOSS, Color(1.0, 0.5, 0.5))
	_add_tinted_source(ts, SOURCE_WALL, Color(0.2, 0.22, 0.28))
	return ts

# Builds a per-source atlas whose texture is the floor sprite multiplied by
# `tint`. Because TileMap doesn't support per-cell modulation, the tint is
# baked into the source texture at TileSet construction time.
func _add_tinted_source(ts: TileSet, source_id: int, tint: Color) -> void:
	var base := load(FLOOR_TEXTURE_PATH) as Texture2D
	var src := TileSetAtlasSource.new()
	if base == null:
		# Defensive: in headless tests the texture may not load. Use a 16x16
		# solid-color image so create_tile() still has a valid texture.
		var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(tint)
		src.texture = ImageTexture.create_from_image(img)
	else:
		var img: Image = base.get_image()
		img.convert(Image.FORMAT_RGBA8)
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
		src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, source_id)
