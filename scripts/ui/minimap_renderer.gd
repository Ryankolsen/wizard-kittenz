class_name MinimapRenderer
extends Control

# Draws one rectangle per revealed room into the host control's rect,
# positioned via the dungeon layout's grid coordinates. Tracer slice (PRD
# #304 / #305) — no corridors, no room-type styling, no player marker.
# Those land in #306 / #307.
#
# The Control re-queries its dungeon + state + layout on draw so a single
# bind() call followed by FloorMapState.mark_revealed (per room enter) is
# enough — the host just calls queue_redraw() when the reveal set changes.

const ROOM_CELL_SIZE: float = 6.0
const ROOM_COLOR := Color(0.85, 0.85, 0.9, 1.0)

var dungeon: Dungeon = null
var floor_state: FloorMapState = null
var layout: DungeonLayout = null

func bind(d: Dungeon, s: FloorMapState, l: DungeonLayout) -> void:
	dungeon = d
	floor_state = s
	layout = l
	queue_redraw()

func _draw() -> void:
	if dungeon == null or floor_state == null or layout == null:
		return
	var target := Rect2(Vector2.ZERO, size)
	var extent := _grid_extent(layout, floor_state.revealed_ids())
	if extent.size() == 0:
		return
	var grid_min: Vector2i = extent["min"]
	var grid_max: Vector2i = extent["max"]
	for rid in rooms_to_draw(dungeon, floor_state):
		if not layout.room_positions.has(rid):
			continue
		var grid_pos: Vector2i = layout.room_positions[rid]
		var center := world_to_minimap(grid_pos, grid_min, grid_max, target)
		var rect := Rect2(
			center - Vector2(ROOM_CELL_SIZE, ROOM_CELL_SIZE) * 0.5,
			Vector2(ROOM_CELL_SIZE, ROOM_CELL_SIZE))
		draw_rect(rect, ROOM_COLOR, true)

# Pure helper — returns the intersection of dungeon room ids and the
# revealed set. Skips stale ids so a corrupt save / off-by-one doesn't
# render rectangles for rooms the dungeon doesn't know about.
static func rooms_to_draw(d: Dungeon, s: FloorMapState) -> Array:
	var ids: Array = []
	if d == null or s == null:
		return ids
	for rid in s.revealed_ids():
		if d.get_room(rid) != null:
			ids.append(rid)
	return ids

# Pure helper — maps a grid cell to a pixel position inside `target`, with
# the grid's bounding box ((grid_min, grid_max)) spanning the target rect's
# full width/height. A degenerate single-cell grid collapses to the rect's
# origin rather than dividing by zero.
static func world_to_minimap(
		grid_pos: Vector2i,
		grid_min: Vector2i,
		grid_max: Vector2i,
		target: Rect2) -> Vector2:
	var span_x: int = grid_max.x - grid_min.x
	var span_y: int = grid_max.y - grid_min.y
	var frac_x: float = 0.0 if span_x == 0 else float(grid_pos.x - grid_min.x) / float(span_x)
	var frac_y: float = 0.0 if span_y == 0 else float(grid_pos.y - grid_min.y) / float(span_y)
	return target.position + Vector2(frac_x * target.size.x, frac_y * target.size.y)

static func _grid_extent(layout: DungeonLayout, ids: Array) -> Dictionary:
	if layout == null or ids.is_empty():
		return {}
	var first := true
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	for rid in ids:
		if not layout.room_positions.has(rid):
			continue
		var p: Vector2i = layout.room_positions[rid]
		if first:
			lo = p
			hi = p
			first = false
		else:
			lo.x = min(lo.x, p.x)
			lo.y = min(lo.y, p.y)
			hi.x = max(hi.x, p.x)
			hi.y = max(hi.y, p.y)
	if first:
		return {}
	return {"min": lo, "max": hi}
