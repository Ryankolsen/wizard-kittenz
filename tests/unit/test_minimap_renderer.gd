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
