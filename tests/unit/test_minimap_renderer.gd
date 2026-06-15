extends GutTest

# MinimapRenderer pure-helper tests. The Control's draw layer is exercised
# only through static helpers so the math is verified without a SceneTree.
# Post-#310 QA: the renderer projects rooms, corridors, and markers
# through a single world-pixel → minimap transform (compute_world_bounds,
# compute_scale, world_to_minimap). A player standing inside a room must
# render INSIDE that room's projected rectangle — the asymmetric grid /
# world transforms that caused the V1 marker drift are gone.

const _STEP: int = DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX

func _make_dungeon() -> Dungeon:
	var d := Dungeon.new()
	d.add_room(Room.make(0, Room.TYPE_START))
	d.add_room(Room.make(1, Room.TYPE_STANDARD))
	d.add_room(Room.make(2, Room.TYPE_STANDARD))
	d.start_id = 0
	d.boss_id = 2
	return d

func _layout_three_in_a_row() -> DungeonLayout:
	# Rooms placed at (0,0), (1,0), (2,0) — a 3-wide horizontal strip.
	var l := DungeonLayout.new()
	l.room_positions[0] = Vector2i(0, 0)
	l.room_positions[1] = Vector2i(1, 0)
	l.room_positions[2] = Vector2i(2, 0)
	l.boss_id = 2
	return l

func test_rooms_to_draw_returns_only_revealed_ids():
	# Renderer projects {revealed rooms ∩ dungeon rooms} so a stale id in
	# the state (e.g. from a load) doesn't render an empty rectangle and a
	# dungeon room that's never been entered stays hidden.
	var d := _make_dungeon()
	var s := FloorMapState.new()
	s.mark_revealed(0)
	s.mark_revealed(2)
	var ids := MinimapRenderer.rooms_to_draw(d, s)
	assert_eq(ids.size(), 2)
	assert_true(ids.has(0))
	assert_true(ids.has(2))
	assert_false(ids.has(1))

func test_rooms_to_draw_ignores_unknown_revealed_ids():
	# Defensive: a revealed id that isn't in the dungeon (corrupt save /
	# off-by-one) must not appear in the draw list, since the renderer
	# can't ask the layout for its grid position.
	var d := _make_dungeon()
	var s := FloorMapState.new()
	s.mark_revealed(0)
	s.mark_revealed(99)
	var ids := MinimapRenderer.rooms_to_draw(d, s)
	assert_eq(ids.size(), 1)
	assert_true(ids.has(0))

# --- world bounds + transform -----------------------------------------------

func test_compute_world_bounds_unions_revealed_rooms():
	# Bounds span from room 0's top-left to room 2's bottom-right. The two
	# revealed rooms are 192px each, separated by a 192+80=272 px step.
	var d := _make_dungeon()
	var l := _layout_three_in_a_row()
	var bounds := MinimapRenderer.compute_world_bounds(d, l, [0, 2])
	# Room 0 origin (0, 0); room 2 (boss, 2x) origin (2*272, 0) = (544, 0).
	# Room 2 is the boss, so its size is BOSS_ROOM_SIZE_PX (384).
	assert_almost_eq(bounds.position.x, 0.0, 0.01)
	assert_almost_eq(bounds.position.y, 0.0, 0.01)
	assert_almost_eq(bounds.size.x, 2.0 * float(_STEP) + float(DungeonLayout.BOSS_ROOM_SIZE_PX), 0.01)
	# Vertical span comes from the boss room (the larger of the two).
	assert_almost_eq(bounds.size.y, float(DungeonLayout.BOSS_ROOM_SIZE_PX), 0.01)

func test_compute_world_bounds_empty_revealed_returns_zero_rect():
	# Defensive: no revealed rooms means no bounds — draw layer short-
	# circuits before calling the transform, but the helper must not crash.
	var d := _make_dungeon()
	var l := _layout_three_in_a_row()
	var bounds := MinimapRenderer.compute_world_bounds(d, l, [])
	assert_almost_eq(bounds.size.x, 0.0, 0.01)
	assert_almost_eq(bounds.size.y, 0.0, 0.01)

func test_compute_scale_preserves_aspect_ratio():
	# A 200x100 world projected into a 100x100 target collapses to a uniform
	# scale of 0.5-minus-margin (the wider axis wins). Letterboxing leaves
	# vertical slack rather than squishing the rooms.
	var world := Rect2(Vector2.ZERO, Vector2(200, 100))
	var target := Rect2(Vector2.ZERO, Vector2(100, 100))
	var scale := MinimapRenderer.compute_scale(world, target)
	var expected := (100.0 - MinimapRenderer.MAP_MARGIN_PX * 2.0) / 200.0
	assert_almost_eq(scale, expected, 0.0001)

func test_world_to_minimap_maps_origin_to_offset_inside_target():
	# The world bounds' top-left corner maps to an interior point of the
	# target rect (offset by the centring + margin), not to (0,0).
	var world := Rect2(Vector2.ZERO, Vector2(200, 200))
	var target := Rect2(Vector2(10, 20), Vector2(100, 100))
	var p := MinimapRenderer.world_to_minimap(world.position, world, target)
	# Square world in square target → no letterboxing, just the margin.
	assert_almost_eq(p.x, 10.0 + MinimapRenderer.MAP_MARGIN_PX, 0.01)
	assert_almost_eq(p.y, 20.0 + MinimapRenderer.MAP_MARGIN_PX, 0.01)

func test_world_to_minimap_player_inside_room_lands_inside_room_rect():
	# Regression for the V1 marker drift: a player standing at the centre
	# of a known room must project to a minimap point that lies inside
	# that room's projected rectangle. With the old asymmetric transform
	# the dot drifted by half a room-step.
	var d := _make_dungeon()
	var l := _layout_three_in_a_row()
	var revealed: Array = [0, 1]
	var bounds := MinimapRenderer.compute_world_bounds(d, l, revealed)
	var target := Rect2(Vector2.ZERO, Vector2(100, 100))
	var scale := MinimapRenderer.compute_scale(bounds, target)
	# Player stands at the centre of room 1.
	var room1_world := MinimapRenderer.room_world_rect(1, d, l)
	var player_world := room1_world.position + room1_world.size * 0.5
	var marker := MinimapRenderer.world_to_minimap(player_world, bounds, target)
	# Room 1's projected rectangle on the minimap.
	var room1_tl := MinimapRenderer.world_to_minimap(room1_world.position, bounds, target)
	var room1_rect := Rect2(room1_tl, room1_world.size * scale)
	assert_true(room1_rect.has_point(marker),
		"Player marker at %s must lie inside room 1's minimap rect %s" % [marker, room1_rect])

func test_world_to_minimap_boss_room_renders_larger_than_standard():
	# Boss rooms are 2x in world space; the unified transform preserves
	# that ratio on the minimap so the boss is visually distinguishable
	# from a standard room.
	var d := _make_dungeon()
	var l := _layout_three_in_a_row()
	var bounds := MinimapRenderer.compute_world_bounds(d, l, [1, 2])
	var target := Rect2(Vector2.ZERO, Vector2(200, 200))
	var scale := MinimapRenderer.compute_scale(bounds, target)
	var standard := MinimapRenderer.room_world_rect(1, d, l).size * scale
	var boss := MinimapRenderer.room_world_rect(2, d, l).size * scale
	# Boss = 384 px world, standard = 192 px world → 2x ratio preserved.
	assert_almost_eq(boss.x / standard.x, 2.0, 0.01)
	assert_almost_eq(boss.y / standard.y, 2.0, 0.01)

# --- room centres + edges ---------------------------------------------------

func test_room_center_world_uses_room_size():
	# Standard room: centre at origin + 96. Boss room: centre at origin + 192.
	var d := _make_dungeon()
	var l := _layout_three_in_a_row()
	var c1 := MinimapRenderer.room_center_world(1, d, l)
	assert_almost_eq(c1.x, float(_STEP) + float(DungeonLayout.ROOM_SIZE_PX) * 0.5, 0.01)
	var c2 := MinimapRenderer.room_center_world(2, d, l)
	assert_almost_eq(c2.x, 2.0 * float(_STEP) + float(DungeonLayout.BOSS_ROOM_SIZE_PX) * 0.5, 0.01)

func test_edge_drawn_when_both_endpoints_revealed():
	# Corridors are gated by reveal: an edge between A and B renders only when
	# BOTH endpoints are revealed. Mark both, helper returns true.
	var s := FloorMapState.new()
	s.mark_revealed(0)
	s.mark_revealed(1)
	assert_true(MinimapRenderer.should_draw_edge(0, 1, s))

func test_edge_not_drawn_when_one_endpoint_unrevealed():
	# Leak guard: a half-revealed corridor would betray the existence of the
	# unrevealed room on the other end.
	var s := FloorMapState.new()
	s.mark_revealed(0)
	assert_false(MinimapRenderer.should_draw_edge(0, 1, s))
	assert_false(MinimapRenderer.should_draw_edge(1, 0, s))

func test_edge_not_drawn_when_neither_revealed():
	var s := FloorMapState.new()
	assert_false(MinimapRenderer.should_draw_edge(0, 1, s))

func test_room_style_for_type_returns_distinct_styles():
	# Each room type must produce a visually distinct style id so the player
	# can tell start from boss from power-up at a glance.
	var styles := {}
	for t in [
			Room.TYPE_START,
			Room.TYPE_STANDARD,
			Room.TYPE_BAR,
			Room.TYPE_POWERUP,
			Room.TYPE_BOSS]:
		var key: String = MinimapRenderer.style_for_room_type(t)
		assert_false(styles.has(key), "Duplicate style for type %s" % t)
		styles[key] = true
	assert_eq(styles.size(), 5)

# --- Slice 5 (#309): co-op teammate markers, gated by local reveal ---

func test_teammate_marker_drawn_when_teammate_room_revealed():
	# Pure helper: a teammate marker is drawable iff the local FloorMapState
	# has revealed the room the teammate is currently in. Fog-of-war is
	# per-player — scouting through a teammate must not reveal new rooms.
	var s := FloorMapState.new()
	s.mark_revealed(1)
	assert_true(MinimapRenderer.should_draw_teammate(1, s))

func test_teammate_marker_hidden_when_room_unrevealed():
	# Story 13: if the local FloorMapState has not revealed the teammate's
	# room, the helper returns false AND teammates_to_draw filters them out
	# from the renderer's draw list.
	var d := _make_dungeon()
	var s := FloorMapState.new()
	s.mark_revealed(0)  # local revealed room 0 only
	assert_false(MinimapRenderer.should_draw_teammate(1, s))
	var snapshots: Array = [{"player_id": "p2", "current_room_id": 1, "world_pos": Vector2.ZERO}]
	var draws := MinimapRenderer.teammates_to_draw(snapshots, d, s)
	assert_eq(draws.size(), 0)

class _InactiveSessionStub:
	var local_player_id: String = "p1"
	var player_ids: Array = ["p1", "p2"]
	var network_sync = null
	func is_active() -> bool:
		return false

func test_no_teammates_in_solo_session():
	# AC: when CoopSession is null OR inactive, the snapshot helper returns
	# []. Guards both the "no session constructed" and "session ended"
	# paths so the renderer never crashes in solo play.
	var d := _make_dungeon()
	var l := DungeonLayout.new()
	assert_eq(MinimapRenderer.teammate_snapshots_from_session(null, d, l, 0).size(), 0)
	var inactive := _InactiveSessionStub.new()
	assert_eq(MinimapRenderer.teammate_snapshots_from_session(inactive, d, l, 0).size(), 0)

func test_teammate_with_unknown_room_excluded():
	# Defensive: a snapshot whose current_room_id is -1 (peer is in a
	# corridor / off-graph) OR points at a room id not in the dungeon
	# (stale state after floor advance, race against teleport) must be
	# silently dropped, not rendered at (0,0) or crash get_room().
	var d := _make_dungeon()
	var s := FloorMapState.new()
	s.mark_revealed(0)
	s.mark_revealed(1)
	s.mark_revealed(99)  # local "revealed" a phantom id too — still excluded
	var snapshots: Array = [
		{"player_id": "p2", "current_room_id": -1, "world_pos": Vector2.ZERO},
		{"player_id": "p3", "current_room_id": 99, "world_pos": Vector2.ZERO},
		{"player_id": "p4", "current_room_id": 1, "world_pos": Vector2.ZERO},
	]
	var draws := MinimapRenderer.teammates_to_draw(snapshots, d, s)
	assert_eq(draws.size(), 1)
	assert_eq(String(draws[0]["player_id"]), "p4")

func test_boss_room_not_drawn_when_unrevealed():
	# Story 7: the boss room stays invisible until the player walks into it.
	# Reveal only the start; the boss id must not appear in rooms_to_draw.
	var d := _make_dungeon()
	var s := FloorMapState.new()
	s.mark_revealed(d.start_id)
	var ids := MinimapRenderer.rooms_to_draw(d, s)
	assert_false(ids.has(d.boss_id), "Boss room must be hidden until revealed")
	assert_true(ids.has(d.start_id))

# --- boss-direction X marker ------------------------------------------------

func test_bounds_ids_includes_boss_even_when_unrevealed():
	# The boss-direction X needs the boss room inside the projected bounds so
	# it stays on the chip. bounds_ids unions the revealed set with the boss
	# id even though the boss room itself is never in rooms_to_draw yet.
	var d := _make_dungeon()
	var l := _layout_three_in_a_row()
	var s := FloorMapState.new()
	s.mark_revealed(0)  # only the start is revealed
	var ids := MinimapRenderer.bounds_ids(d, s, l)
	assert_true(ids.has(0), "revealed start stays in the bounds set")
	assert_true(ids.has(d.boss_id), "boss must widen the bounds even unrevealed")

func test_bounds_ids_no_duplicate_boss_when_revealed():
	# Once the boss room is revealed it's already in the set; bounds_ids must
	# not append a second copy.
	var d := _make_dungeon()
	var l := _layout_three_in_a_row()
	var s := FloorMapState.new()
	s.mark_revealed(0)
	s.mark_revealed(d.boss_id)
	var ids := MinimapRenderer.bounds_ids(d, s, l)
	assert_eq(ids.count(d.boss_id), 1, "boss id appears exactly once")

func test_bounds_ids_skips_boss_with_no_layout_position():
	# Defensive: a boss id absent from the layout (degenerate dungeon) is not
	# added — projecting it would ask the layout for a position it lacks.
	var d := _make_dungeon()
	var l := DungeonLayout.new()
	l.room_positions[0] = Vector2i(0, 0)  # boss (id 2) deliberately missing
	var s := FloorMapState.new()
	s.mark_revealed(0)
	var ids := MinimapRenderer.bounds_ids(d, s, l)
	assert_false(ids.has(d.boss_id), "boss without a layout position is skipped")
