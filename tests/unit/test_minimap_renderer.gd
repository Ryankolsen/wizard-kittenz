extends GutTest

# MinimapRenderer pure-helper tests. The Control's draw layer is exercised
# only through static helpers so the math is verified without a SceneTree.
# Slice 1 (PRD #304): rooms are rectangles at layout-derived positions
# scaled to fit the host chip rect. No types, corridors, or player marker
# yet — those come in slices 2 / 3.

func _make_dungeon() -> Dungeon:
	var d := Dungeon.new()
	d.add_room(Room.make(0, Room.TYPE_START))
	d.add_room(Room.make(1, Room.TYPE_STANDARD))
	d.add_room(Room.make(2, Room.TYPE_STANDARD))
	d.start_id = 0
	d.boss_id = 2
	return d

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

func test_world_to_minimap_transform_scales_into_target_rect():
	# Given a known grid extent ((0,0)..(2,1)) and a 100x100 target rect,
	# the corner cells map to the rect's corners (with a half-cell inset
	# so each rectangle's center sits at the expected fraction).
	var target := Rect2(Vector2.ZERO, Vector2(100, 100))
	var grid_min := Vector2i(0, 0)
	var grid_max := Vector2i(2, 1)
	# Top-left grid cell (0,0) maps near rect origin.
	var p00 := MinimapRenderer.world_to_minimap(Vector2i(0, 0), grid_min, grid_max, target)
	assert_true(target.has_point(p00))
	assert_almost_eq(p00.x, 0.0, 0.01)
	assert_almost_eq(p00.y, 0.0, 0.01)
	# Bottom-right grid cell (2,1) maps to the opposite corner area.
	var p21 := MinimapRenderer.world_to_minimap(Vector2i(2, 1), grid_min, grid_max, target)
	assert_almost_eq(p21.x, 100.0, 0.01)
	assert_almost_eq(p21.y, 100.0, 0.01)

func test_world_to_minimap_middle_cell_lands_at_expected_fraction():
	# Middle column (x=1) on a 0..2 range lands halfway across width.
	var target := Rect2(Vector2.ZERO, Vector2(100, 100))
	var p := MinimapRenderer.world_to_minimap(
		Vector2i(1, 0), Vector2i(0, 0), Vector2i(2, 1), target)
	assert_almost_eq(p.x, 50.0, 0.01)

func test_world_to_minimap_single_cell_grid_collapses_to_rect_origin():
	# Degenerate: only one room revealed (grid_min == grid_max). The cell
	# lands at the rect's origin rather than dividing by zero.
	var target := Rect2(Vector2(10, 20), Vector2(50, 50))
	var p := MinimapRenderer.world_to_minimap(
		Vector2i(3, 3), Vector2i(3, 3), Vector2i(3, 3), target)
	assert_almost_eq(p.x, 10.0, 0.01)
	assert_almost_eq(p.y, 20.0, 0.01)

# --- Slice 2 (#306): corridors, room-type styling, local player dot ---

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

func test_player_marker_position_uses_world_to_minimap_transform():
	# The player marker is positioned in the same coordinate space as the
	# rooms: feed a player world position whose fractional grid coord matches
	# a known room's grid_pos and assert the marker lands at the same minimap
	# point world_to_minimap would produce for that room.
	var target := Rect2(Vector2.ZERO, Vector2(100, 100))
	var grid_min := Vector2i(0, 0)
	var grid_max := Vector2i(2, 1)
	# Player standing exactly in the middle room (grid (1,0)) → world origin
	# (step, 0) where step = ROOM_SIZE_PX + CORRIDOR_WIDTH_PX.
	var step: int = DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX
	var player_world := Vector2(float(step) * 1.0, 0.0)
	var marker := MinimapRenderer.player_to_minimap(
		player_world, grid_min, grid_max, target)
	var room := MinimapRenderer.world_to_minimap(
		Vector2i(1, 0), grid_min, grid_max, target)
	assert_almost_eq(marker.x, room.x, 0.01)
	assert_almost_eq(marker.y, room.y, 0.01)

# --- Slice 5 (#309): co-op teammate markers, gated by local reveal ---

func test_teammate_marker_position_uses_world_to_minimap_transform():
	# Teammate markers share the local player's world→minimap transform; given
	# the teammate's world position, the renderer maps them via teammate_to_minimap
	# which must equal player_to_minimap for the same inputs (the two markers
	# are conceptually the same projection — only the color/source differs).
	var target := Rect2(Vector2.ZERO, Vector2(100, 100))
	var grid_min := Vector2i(0, 0)
	var grid_max := Vector2i(2, 1)
	var step: int = DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX
	var teammate_world := Vector2(float(step) * 1.0, 0.0)
	var teammate_pt := MinimapRenderer.teammate_to_minimap(
		teammate_world, grid_min, grid_max, target)
	var via_player := MinimapRenderer.player_to_minimap(
		teammate_world, grid_min, grid_max, target)
	assert_almost_eq(teammate_pt.x, via_player.x, 0.01)
	assert_almost_eq(teammate_pt.y, via_player.y, 0.01)

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
