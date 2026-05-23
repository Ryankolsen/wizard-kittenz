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
const BAR_ENTRANCE_TEXTURE_PATH := "res://assets/sprites/bar_entrance.png"
const TILE_SIZE := 16
const ROOM_TILES := 12
const BOSS_ROOM_TILES := 24
const CORRIDOR_TILES := 5

const SOURCE_FLOOR := 0
const SOURCE_START := 1
const SOURCE_BOSS := 2
const SOURCE_WALL := 3
const SOURCE_BAR_ENTRANCE := 4

# Tile coords of every bar-entrance cell painted on the last paint() call.
# Exposed for tests and the placement layer (the spawn / scene-transition code
# can read this to position the in-world bar door trigger on the matching tile).
var bar_entrance_tiles: Array = []

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
		var room_tiles: int = BOSS_ROOM_TILES if rid == boss_id else ROOM_TILES
		for y in range(room_tiles):
			for x in range(room_tiles):
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
	_repaint_variant_room(tilemap, layout, boss_id, SOURCE_BOSS, BOSS_ROOM_TILES)

	_paint_walls(tilemap, floor_cells)

	# Bar room doorway markers go last so they override the corridor floor that
	# was painted through the bar's perimeter cells. No-op when `dungeon` is null
	# or contains no bar room (legacy callers / tests).
	bar_entrance_tiles = []
	_paint_bar_entrances(tilemap, layout, dungeon)

func _repaint_variant_room(tilemap: TileMap, layout: DungeonLayout, rid: int, source_id: int, room_tiles: int = ROOM_TILES) -> void:
	if rid < 0 or not layout.room_positions.has(rid):
		return
	var step_tiles: int = ROOM_TILES + CORRIDOR_TILES
	var grid_pos: Vector2i = layout.room_positions[rid]
	var origin := Vector2i(grid_pos.x * step_tiles, grid_pos.y * step_tiles)
	for y in range(room_tiles):
		for x in range(room_tiles):
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
	_add_bar_entrance_source(ts, SOURCE_BAR_ENTRANCE)
	return ts

# Bar entrance uses the standalone bar_entrance.png art, not a tint of floor.png
# — it's a hand-authored doorway sprite, not a floor variant. Image is resized
# to TILE_SIZE because TileMap stamps one source-region per cell and the painter
# uses 16 px tiles everywhere.
func _add_bar_entrance_source(ts: TileSet, source_id: int) -> void:
	var base := load(BAR_ENTRANCE_TEXTURE_PATH) as Texture2D
	var src := TileSetAtlasSource.new()
	if base == null:
		# Defensive: in headless tests the texture may not load. Use a solid
		# warm-brown so create_tile() still has a valid texture.
		var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.6, 0.35, 0.15))
		src.texture = ImageTexture.create_from_image(img)
	else:
		var img: Image = base.get_image()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != TILE_SIZE or img.get_height() != TILE_SIZE:
			img.resize(TILE_SIZE, TILE_SIZE)
		src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, source_id)

# Paint one entrance per bar room — a 2x2 footprint on the perimeter facing the
# bar's parent room (the room the player arrives through). The 2x2 extends one
# cell inward along the door-normal axis so every cell lands on bar floor
# (walkable). The bar's other corridor mouths (its two outgoing edges) stay as
# plain floor: still walkable, just no door visual.
const BAR_DOOR_FOOTPRINT := 2
func _paint_bar_entrances(tilemap: TileMap, layout: DungeonLayout, dungeon: Dungeon) -> void:
	if dungeon == null:
		return
	var step_tiles: int = ROOM_TILES + CORRIDOR_TILES
	for room in dungeon.rooms:
		if room.type != Room.TYPE_BAR:
			continue
		var bar_id: int = room.id
		if not layout.room_positions.has(bar_id):
			continue
		var parent_id: int = _find_parent_id(dungeon, bar_id)
		# Fall back to any connected room if no parent edge exists (defensive —
		# the generator always wires a parent into the bar).
		if parent_id == -1:
			for pair in layout.corridors:
				if pair[0] == bar_id and layout.room_positions.has(pair[1]):
					parent_id = pair[1]
					break
				if pair[1] == bar_id and layout.room_positions.has(pair[0]):
					parent_id = pair[0]
					break
		if parent_id == -1 or not layout.room_positions.has(parent_id):
			continue
		var bar_grid: Vector2i = layout.room_positions[bar_id]
		var bar_origin := Vector2i(bar_grid.x * step_tiles, bar_grid.y * step_tiles)
		var bar_cx: int = bar_origin.x + ROOM_TILES / 2
		var bar_cy: int = bar_origin.y + ROOM_TILES / 2
		var parent_grid: Vector2i = layout.room_positions[parent_id]
		var parent_center := parent_grid * step_tiles + Vector2i(ROOM_TILES / 2, ROOM_TILES / 2)
		var footprint: Array = _bar_entrance_footprint(bar_origin, bar_cx, bar_cy, parent_center)
		for cell in footprint:
			tilemap.set_cell(0, cell, SOURCE_BAR_ENTRANCE, Vector2i(0, 0))
			bar_entrance_tiles.append(cell)

# The bar's parent is the room that lists bar_id in its outgoing connections.
# Returns -1 if none found.
func _find_parent_id(dungeon: Dungeon, bar_id: int) -> int:
	for r in dungeon.rooms:
		if r.id == bar_id:
			continue
		if r.connections.has(bar_id):
			return r.id
	return -1

# Pick the 2x2 footprint of the bar-room doorway on the perimeter facing
# `other_center` along the dominant axis. Two cells span the door's width
# along the perimeter edge; the other two extend one tile into the bar
# interior along the door-normal axis. All four cells land on bar floor.
func _bar_entrance_footprint(bar_origin: Vector2i, bar_cx: int, bar_cy: int, other_center: Vector2i) -> Array:
	var dx: int = other_center.x - bar_cx
	var dy: int = other_center.y - bar_cy
	var max_x: int = bar_origin.x + ROOM_TILES - 1
	var max_y: int = bar_origin.y + ROOM_TILES - 1
	var cells: Array = []
	if absi(dx) >= absi(dy):
		# East (dx>0) or west (dx<=0) edge. Span y in [bar_cy, bar_cy+1],
		# extend inward along x.
		var edge_x: int
		var inward_x: int
		if dx > 0:
			edge_x = max_x
			inward_x = max_x - 1
		else:
			edge_x = bar_origin.x
			inward_x = bar_origin.x + 1
		for y in [bar_cy, bar_cy + 1]:
			cells.append(Vector2i(edge_x, y))
			cells.append(Vector2i(inward_x, y))
	else:
		# North (dy<=0) or south (dy>0) edge. Span x in [bar_cx, bar_cx+1],
		# extend inward along y.
		var edge_y: int
		var inward_y: int
		if dy > 0:
			edge_y = max_y
			inward_y = max_y - 1
		else:
			edge_y = bar_origin.y
			inward_y = bar_origin.y + 1
		for x in [bar_cx, bar_cx + 1]:
			cells.append(Vector2i(x, edge_y))
			cells.append(Vector2i(x, inward_y))
	return cells

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
