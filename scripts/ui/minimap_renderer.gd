class_name MinimapRenderer
extends Control

# Draws revealed rooms, the corridors between them, and the local player /
# teammate markers onto the host control's rect. Tracer slice (PRD #304)
# evolved through slice 2 (#306) and 5 (#309); this revision (post-#310 QA)
# replaces the asymmetric grid/world transforms with a single world-pixel →
# minimap transform so room rectangles, corridor endpoints, and the player
# marker all live in the same coordinate space. A player standing in the
# centre of a room renders inside that room's rectangle, not offset by a
# half-step.
#
# The Control re-queries its dungeon + state + layout on draw so a single
# bind() call followed by FloorMapState.mark_revealed (per room enter) is
# enough — the host just calls queue_redraw() when the reveal set changes.

const CORRIDOR_COLOR := Color(0.55, 0.6, 0.7, 1.0)
const CORRIDOR_WIDTH: float = 1.5
const PLAYER_MARKER_RADIUS: float = 2.5
const PLAYER_MARKER_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const TEAMMATE_MARKER_RADIUS: float = 2.0
const TEAMMATE_MARKER_COLOR := Color(0.4, 0.85, 1.0, 1.0)
# Inner margin so the projected world bounds don't kiss the chip border.
const MAP_MARGIN_PX: float = 4.0

# Per-type colors. Distinct hues so the player can tell at-a-glance which
# rectangle is the boss vs. the bar vs. start; style_for_room_type() exposes
# the same map as opaque string ids for the test layer.
const STYLE_START := "start"
const STYLE_STANDARD := "standard"
const STYLE_BAR := "bar"
const STYLE_POWERUP := "powerup"
const STYLE_BOSS := "boss"
const ROOM_COLOR := Color(0.85, 0.85, 0.9, 1.0)
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
# the marker tracks the player's movement inside the current room.
var player_world_pos: Vector2 = Vector2.ZERO
# Slice 5 (#309): caller (MinimapHUD / FullscreenMapOverlay) refreshes this
# each frame from CoopSession.network_sync; the renderer just draws what
# it's told.
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
	var revealed := floor_state.revealed_ids()
	var world_bounds := compute_world_bounds(dungeon, layout, revealed)
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return
	var scale := compute_scale(world_bounds, target)
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
			var c_a := room_center_world(room.id, dungeon, layout)
			var c_b := room_center_world(next_id, dungeon, layout)
			var p_a := world_to_minimap(c_a, world_bounds, target)
			var p_b := world_to_minimap(c_b, world_bounds, target)
			draw_line(p_a, p_b, CORRIDOR_COLOR, CORRIDOR_WIDTH)
	for rid in rooms_to_draw(dungeon, floor_state):
		if not layout.room_positions.has(rid):
			continue
		var room2 := dungeon.get_room(rid)
		var room_world := room_world_rect(rid, dungeon, layout)
		var tl := world_to_minimap(room_world.position, world_bounds, target)
		var size_mini := room_world.size * scale
		var style := style_for_room_type(room2.type if room2 != null else Room.TYPE_STANDARD)
		var color: Color = STYLE_COLORS.get(style, ROOM_COLOR)
		draw_rect(Rect2(tl, size_mini), color, true)
	# Player marker on top. Only draw when the player is inside a revealed
	# room — otherwise a marker dragged through a corridor would leak the
	# unrevealed room at the other end.
	if _player_in_revealed_room():
		var marker := world_to_minimap(player_world_pos, world_bounds, target)
		draw_circle(marker, PLAYER_MARKER_RADIUS, PLAYER_MARKER_COLOR)
	# Slice 5 (#309): teammate markers — filtered by reveal so teammates in
	# unrevealed rooms paint nothing (story 13).
	for snap in teammates_to_draw(teammate_snapshots, dungeon, floor_state):
		var t_world: Vector2 = snap.get("world_pos", Vector2.ZERO)
		var t_pt := world_to_minimap(t_world, world_bounds, target)
		draw_circle(t_pt, TEAMMATE_MARKER_RADIUS, TEAMMATE_MARKER_COLOR)

func _player_in_revealed_room() -> bool:
	if dungeon == null or layout == null or floor_state == null:
		return false
	for rid in floor_state.revealed_ids():
		if not layout.room_positions.has(rid):
			continue
		var bounds := room_world_rect(rid, dungeon, layout)
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

# Pure helper — world-pixel bounding rect of all revealed rooms. The
# renderer projects everything (rooms, corridors, markers) through this
# rect so a single transform places them all in the same coordinate
# space. Boss rooms contribute their (2x) size, not the standard size.
# Empty / unknown revealed sets collapse to a zero-size Rect2.
static func compute_world_bounds(d: Dungeon, l: DungeonLayout, revealed: Array) -> Rect2:
	if d == null or l == null:
		return Rect2()
	var first := true
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for rid in revealed:
		if d.get_room(rid) == null:
			continue
		if not l.room_positions.has(rid):
			continue
		var room_rect := room_world_rect(rid, d, l)
		if first:
			lo = room_rect.position
			hi = room_rect.position + room_rect.size
			first = false
		else:
			lo.x = min(lo.x, room_rect.position.x)
			lo.y = min(lo.y, room_rect.position.y)
			hi.x = max(hi.x, room_rect.position.x + room_rect.size.x)
			hi.y = max(hi.y, room_rect.position.y + room_rect.size.y)
	if first:
		return Rect2()
	return Rect2(lo, hi - lo)

# Pure helper — uniform scale factor from world to minimap, fitting
# world_bounds inside target with aspect ratio preserved. The minimap
# letterboxes inside the chip when the floor's world bounds aren't a
# perfect match for the chip's aspect.
static func compute_scale(world_bounds: Rect2, target: Rect2) -> float:
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return 1.0
	var inner_w: float = max(0.0, target.size.x - MAP_MARGIN_PX * 2.0)
	var inner_h: float = max(0.0, target.size.y - MAP_MARGIN_PX * 2.0)
	if inner_w <= 0.0 or inner_h <= 0.0:
		return 0.0
	return min(inner_w / world_bounds.size.x, inner_h / world_bounds.size.y)

# Pure helper — maps a world-pixel point into `target`, applying a uniform
# scale (compute_scale) and centring the projected world bounds inside the
# target rect. Rooms, corridor endpoints, the player, and teammates all go
# through this one function so they share an identical projection.
static func world_to_minimap(world: Vector2, world_bounds: Rect2, target: Rect2) -> Vector2:
	if world_bounds.size.x <= 0.0 and world_bounds.size.y <= 0.0:
		return target.position
	var scale := compute_scale(world_bounds, target)
	var projected := world_bounds.size * scale
	var offset := target.position + (target.size - projected) * 0.5
	return offset + (world - world_bounds.position) * scale

# Pure helper — world-pixel rect of a room. Boss rooms are 2x; everything
# else is the standard size. Shared by compute_world_bounds, the draw
# layer, and _player_in_revealed_room so all three agree.
static func room_world_rect(rid: int, d: Dungeon, l: DungeonLayout) -> Rect2:
	if d == null or l == null or not l.room_positions.has(rid):
		return Rect2()
	var step: int = DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX
	var grid: Vector2i = l.room_positions[rid]
	var origin := Vector2(float(grid.x * step), float(grid.y * step))
	var sz: int = DungeonLayout.BOSS_ROOM_SIZE_PX if rid == d.boss_id else DungeonLayout.ROOM_SIZE_PX
	return Rect2(origin, Vector2(sz, sz))

# Pure helper — world-pixel centre of a room. Sibling to room_world_rect;
# corridor endpoints use this so the connecting line lands on the centre
# of each room rectangle rather than its corner.
static func room_center_world(rid: int, d: Dungeon, l: DungeonLayout) -> Vector2:
	var r := room_world_rect(rid, d, l)
	return r.position + r.size * 0.5

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

# Pure helper — teammate marker visibility (slice 5 / #309). Mirrors
# fog-of-war for rooms: a teammate in a room the LOCAL player has not
# revealed is invisible, so scouting via teammates cannot defeat the
# per-player reveal set (story 13).
static func should_draw_teammate(teammate_room_id: int, s: FloorMapState) -> bool:
	if s == null:
		return false
	return s.is_revealed(teammate_room_id)

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
	for room in d.rooms:
		if not l.room_positions.has(room.id):
			continue
		if room_world_rect(room.id, d, l).has_point(world):
			return room.id
	return -1
