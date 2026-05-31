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
const CORRIDOR_COLOR := Color(0.55, 0.6, 0.7, 1.0)
const CORRIDOR_WIDTH: float = 1.5
const PLAYER_MARKER_RADIUS: float = 2.5
const PLAYER_MARKER_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const TEAMMATE_MARKER_RADIUS: float = 2.0
const TEAMMATE_MARKER_COLOR := Color(0.4, 0.85, 1.0, 1.0)

# Per-type colors. Distinct hues so the player can tell at-a-glance which
# rectangle is the boss vs. the bar vs. start; style_for_room_type() exposes
# the same map as opaque string ids for the test layer.
const STYLE_START := "start"
const STYLE_STANDARD := "standard"
const STYLE_BAR := "bar"
const STYLE_POWERUP := "powerup"
const STYLE_BOSS := "boss"
const STYLE_COLORS := {
	STYLE_START: Color(0.4, 0.85, 0.5, 1.0),
	STYLE_STANDARD: Color(0.85, 0.85, 0.9, 1.0),
	STYLE_BAR: Color(0.9, 0.7, 0.3, 1.0),
	STYLE_POWERUP: Color(0.5, 0.7, 1.0, 1.0),
	STYLE_BOSS: Color(0.95, 0.3, 0.3, 1.0),
}

var dungeon: Dungeon = null
var floor_state: FloorMapState = null
var layout: DungeonLayout = null
# Current player world-pixel position. main_scene pokes this each frame so
# the marker tracks the player's movement inside the current room, not just
# the room's grid cell. Vector2.ZERO is a safe default — it'll render at the
# top-left of the chip until the first poke, which is invisible behind the
# revealed start rectangle.
var player_world_pos: Vector2 = Vector2.ZERO
# Slice 5 (#309): caller (MinimapHUD / FullscreenMapOverlay) refreshes this
# each frame from CoopSession.network_sync; the renderer just draws what
# it's told. Empty array in solo / inactive session → zero markers.
var teammate_snapshots: Array = []

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
	# Corridors first so room rectangles sit on top of line endpoints. Iterate
	# the dungeon's directed edges; should_draw_edge gates each one on reveal.
	for room in dungeon.rooms:
		if not layout.room_positions.has(room.id):
			continue
		for next_id in room.connections:
			if not layout.room_positions.has(next_id):
				continue
			if not should_draw_edge(room.id, next_id, floor_state):
				continue
			var p_a := world_to_minimap(layout.room_positions[room.id], grid_min, grid_max, target)
			var p_b := world_to_minimap(layout.room_positions[next_id], grid_min, grid_max, target)
			draw_line(p_a, p_b, CORRIDOR_COLOR, CORRIDOR_WIDTH)
	for rid in rooms_to_draw(dungeon, floor_state):
		if not layout.room_positions.has(rid):
			continue
		var room2 := dungeon.get_room(rid)
		var grid_pos: Vector2i = layout.room_positions[rid]
		var center := world_to_minimap(grid_pos, grid_min, grid_max, target)
		var style := style_for_room_type(room2.type if room2 != null else Room.TYPE_STANDARD)
		var color: Color = STYLE_COLORS.get(style, ROOM_COLOR)
		var rect := Rect2(
			center - Vector2(ROOM_CELL_SIZE, ROOM_CELL_SIZE) * 0.5,
			Vector2(ROOM_CELL_SIZE, ROOM_CELL_SIZE))
		draw_rect(rect, color, true)
	# Player marker on top. Only draw when the player is inside a revealed
	# room — otherwise a marker dragged through a corridor would leak the
	# unrevealed room at the other end.
	if _player_in_revealed_room():
		var marker := player_to_minimap(player_world_pos, grid_min, grid_max, target)
		draw_circle(marker, PLAYER_MARKER_RADIUS, PLAYER_MARKER_COLOR)
	# Slice 5 (#309): teammate markers — filtered by reveal so teammates in
	# unrevealed rooms paint nothing (story 13).
	for snap in teammates_to_draw(teammate_snapshots, dungeon, floor_state):
		var t_world: Vector2 = snap.get("world_pos", Vector2.ZERO)
		var t_pt := teammate_to_minimap(t_world, grid_min, grid_max, target)
		draw_circle(t_pt, TEAMMATE_MARKER_RADIUS, TEAMMATE_MARKER_COLOR)

func _player_in_revealed_room() -> bool:
	if dungeon == null or layout == null or floor_state == null:
		return false
	for rid in floor_state.revealed_ids():
		if not layout.room_positions.has(rid):
			continue
		var grid: Vector2i = layout.room_positions[rid]
		var step: int = DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX
		var origin := Vector2(float(grid.x * step), float(grid.y * step))
		var room_size: int = DungeonLayout.BOSS_ROOM_SIZE_PX if rid == dungeon.boss_id else DungeonLayout.ROOM_SIZE_PX
		var bounds := Rect2(origin, Vector2(room_size, room_size))
		if bounds.has_point(player_world_pos):
			return true
	return false

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

# Pure helper — a corridor edge between rooms A and B renders iff BOTH
# endpoints are revealed. Mirrors fog-of-war on rooms: a corridor leaking
# out of an unrevealed room would betray its existence.
static func should_draw_edge(a: int, b: int, s: FloorMapState) -> bool:
	if s == null:
		return false
	return s.is_revealed(a) and s.is_revealed(b)

# Pure helper — maps a Room.TYPE_* string to an opaque style id. Tests rely
# on distinct ids per type; the draw layer looks the id up in STYLE_COLORS.
# Unknown types fall back to STYLE_STANDARD so a future type added to Room
# still renders something rather than being silently invisible.
static func style_for_room_type(room_type: String) -> String:
	match room_type:
		Room.TYPE_START:
			return STYLE_START
		Room.TYPE_BAR:
			return STYLE_BAR
		Room.TYPE_POWERUP:
			return STYLE_POWERUP
		Room.TYPE_BOSS:
			return STYLE_BOSS
		_:
			return STYLE_STANDARD

# Pure helper — maps the player's WORLD pixel position (Player.global_position)
# into the minimap rect using the same transform as world_to_minimap. The
# inverse of DungeonLayout.grid_to_world is "world / step", which turns the
# player's world pos into a fractional grid coord; that coord then projects
# into `target` the same way a room cell does. Keeps the marker geometrically
# co-located with the room rectangle whose bounds contain the player.
static func player_to_minimap(
		player_world: Vector2,
		grid_min: Vector2i,
		grid_max: Vector2i,
		target: Rect2) -> Vector2:
	var step: float = float(DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX)
	var frac_grid := Vector2(player_world.x / step, player_world.y / step)
	var span_x: int = grid_max.x - grid_min.x
	var span_y: int = grid_max.y - grid_min.y
	var frac_x: float = 0.0 if span_x == 0 else (frac_grid.x - float(grid_min.x)) / float(span_x)
	var frac_y: float = 0.0 if span_y == 0 else (frac_grid.y - float(grid_min.y)) / float(span_y)
	return target.position + Vector2(frac_x * target.size.x, frac_y * target.size.y)

# Pure helper — teammate marker visibility (slice 5 / #309). Mirrors
# fog-of-war for rooms: a teammate in a room the LOCAL player has not
# revealed is invisible, so scouting via teammates cannot defeat the
# per-player reveal set (story 13).
static func should_draw_teammate(teammate_room_id: int, s: FloorMapState) -> bool:
	if s == null:
		return false
	return s.is_revealed(teammate_room_id)

# Pure helper — teammate world position into the minimap rect. Identical to
# player_to_minimap (the projection is the same); exposed separately so the
# call sites in _draw read self-documentingly and a future change to teammate
# projection (e.g. clamped-to-room-center) doesn't have to thread an enum.
# Pure helper — filter a list of teammate snapshots down to the ones the
# renderer should draw. A snapshot is a Dictionary with at least
# "current_room_id" (int) and "world_pos" (Vector2). Teammates whose room
# is unrevealed, unknown to the dungeon, or marked -1 are silently dropped
# (story 13 / defensive against stale network state).
static func teammates_to_draw(snapshots: Array, d: Dungeon, s: FloorMapState) -> Array:
	var out: Array = []
	if d == null or s == null:
		return out
	for snap in snapshots:
		var rid: int = int(snap.get("current_room_id", -1))
		if rid < 0:
			continue
		if d.get_room(rid) == null:
			continue
		if not should_draw_teammate(rid, s):
			continue
		out.append(snap)
	return out

# Pure helper — pull teammate position snapshots from a CoopSession in a
# read-only way. Duck-typed `session` arg (Variant) so the test layer can
# pass a stub without standing up a live session; the production caller
# passes the real CoopSession. Returns [] when null/inactive or sync is
# absent. Each snapshot is a Dictionary {player_id, current_room_id,
# world_pos} — current_room_id is derived via spatial containment so this
# helper introduces no new networking shape (story 11 / AC: read-only).
static func teammate_snapshots_from_session(
		session,
		d: Dungeon,
		l: DungeonLayout,
		now_ms: int) -> Array:
	var out: Array = []
	if session == null:
		return out
	if not session.is_active():
		return out
	var sync = session.network_sync
	if sync == null:
		return out
	var local_id: String = session.local_player_id
	for pid in session.player_ids:
		if String(pid) == local_id:
			continue
		var pos: Vector2 = sync.get_display_position_at(pid, now_ms)
		var rid: int = room_id_at_world_pos(pos, d, l)
		out.append({"player_id": String(pid), "current_room_id": rid, "world_pos": pos})
	return out

# Pure helper — spatial containment of a world position against the dungeon's
# rooms. Returns -1 when no room contains the point (corridor / outside the
# graph). Used by teammate_snapshots_from_session to label a remote peer's
# room without inventing a new wire field.
static func room_id_at_world_pos(world: Vector2, d: Dungeon, l: DungeonLayout) -> int:
	if d == null or l == null:
		return -1
	var step: int = DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX
	for room in d.rooms:
		if not l.room_positions.has(room.id):
			continue
		var grid: Vector2i = l.room_positions[room.id]
		var origin := Vector2(float(grid.x * step), float(grid.y * step))
		var room_size: int = DungeonLayout.BOSS_ROOM_SIZE_PX if room.id == d.boss_id else DungeonLayout.ROOM_SIZE_PX
		var bounds := Rect2(origin, Vector2(room_size, room_size))
		if bounds.has_point(world):
			return room.id
	return -1

static func teammate_to_minimap(
		teammate_world: Vector2,
		grid_min: Vector2i,
		grid_max: Vector2i,
		target: Rect2) -> Vector2:
	return player_to_minimap(teammate_world, grid_min, grid_max, target)

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
