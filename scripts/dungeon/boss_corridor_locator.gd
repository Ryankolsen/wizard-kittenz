class_name BossCorridorLocator
extends RefCounted

# Pure module that returns the world-pixel position for the pre-boss healing
# box (#374). The boss is a terminal node with exactly one incoming corridor
# (layout invariant: parent.y < boss.y so the corridor enters from the north).
# The returned point sits on the vertical leg of that corridor — same column as
# the painter draws the corridor tiles (boss_grid.x * step_tiles + ROOM_TILES/2
# in tile coords), and y centered between the parent room's south wall and the
# boss room's north wall so the box renders cleanly inside the corridor strip.
#
# Returns Vector2.ZERO as a "no corridor" sentinel for degenerate inputs (null
# dungeon/layout, missing boss room, boss with no incoming edge) so main_scene
# can detect and skip the spawn without crashing.

static func locate(dungeon: Dungeon, layout: DungeonLayout) -> Vector2:
	if dungeon == null or layout == null:
		return Vector2.ZERO
	var boss_id: int = dungeon.boss_id
	if boss_id < 0 or not layout.room_positions.has(boss_id):
		return Vector2.ZERO
	var parent_id: int = -1
	for pair in layout.corridors:
		if pair.size() >= 2 and pair[1] == boss_id and layout.room_positions.has(pair[0]):
			parent_id = pair[0]
			break
	if parent_id == -1:
		return Vector2.ZERO

	var boss_grid: Vector2i = layout.room_positions[boss_id]
	var parent_grid: Vector2i = layout.room_positions[parent_id]
	var step_px: int = DungeonLayout.ROOM_SIZE_PX + DungeonLayout.CORRIDOR_WIDTH_PX
	var half_tile: float = float(DungeonLayout.TILE_SIZE_PX) / 2.0

	# Painter draws the vertical corridor leg at b_center.x in tile coords, i.e.
	# boss_grid.x * step_tiles + ROOM_TILES/2. In pixels that's the standard
	# room's center column (ROOM_SIZE_PX/2) within the boss cell, plus half a
	# tile so the box centers on the tile pixel-center rather than its origin.
	var corridor_x: float = float(boss_grid.x) * step_px + DungeonLayout.ROOM_SIZE_PX / 2.0 + half_tile

	# Place the box in the corridor strip between the parent room's south wall
	# and the boss room's north wall. Standard rooms are ROOM_SIZE_PX tall, so
	# parent_south = parent_grid.y * step_px + ROOM_SIZE_PX and boss_north =
	# boss_grid.y * step_px. Midpoint sits squarely inside the corridor.
	var parent_south_y: float = float(parent_grid.y) * step_px + DungeonLayout.ROOM_SIZE_PX
	var boss_north_y: float = float(boss_grid.y) * step_px
	var corridor_y: float = (parent_south_y + boss_north_y) / 2.0

	return Vector2(corridor_x, corridor_y)
