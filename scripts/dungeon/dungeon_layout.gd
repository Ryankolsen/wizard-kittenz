class_name DungeonLayout
extends RefCounted

# Pure-data product of DungeonLayoutEngine.compute(). Holds the spatial
# embedding of a dungeon graph: a grid position per room id and the list of
# directed corridor edges. No scene-tree references — the rendering layer
# (multi-room tilemap, exit door placement) consumes this.

# Tile-derived pixel sizes that match DungeonTilemapPainter's authored constants
# (ROOM_TILES * TILE_SIZE, CORRIDOR_TILES * TILE_SIZE). Duplicated here so the
# data layer can answer world-position queries without importing the painter.
# Keep these in sync with the painter — both layers consume the same map.
const ROOM_SIZE_PX: int = 192
const CORRIDOR_WIDTH_PX: int = 80

var room_positions: Dictionary = {}
var corridors: Array = []

# Map a grid position to a world pixel origin. The renderer adds room-local
# offsets on top of this. `room_size` is the room's tile-span in pixels;
# `corridor_width` is the gap between rooms used for the connecting corridor.
func grid_to_world(grid_pos: Vector2i, room_size: int, corridor_width: int) -> Vector2:
	var step: int = room_size + corridor_width
	return Vector2(grid_pos.x * step, grid_pos.y * step)

# World-pixel center of a placed room. Used by RoomSpawnPlanner to assign
# spawn_position to per-room EnemyData so the scene-tree spawner can drop the
# enemy at the right coordinate. Returns Vector2.ZERO for unknown room ids
# (mirrors the "no position" sentinel on EnemyData.spawn_position) so a typo
# / stale id never crashes the spawner.
func room_center_world(room_id: int) -> Vector2:
	if not room_positions.has(room_id):
		return Vector2.ZERO
	var origin := grid_to_world(room_positions[room_id], ROOM_SIZE_PX, CORRIDOR_WIDTH_PX)
	return origin + Vector2(ROOM_SIZE_PX / 2, ROOM_SIZE_PX / 2)

# World position and rotation for the exit door at the boss room's corridor
# entrance. Returns {"position": Vector2, "rotation": float (radians)}.
#
# The corridor is L-shaped: horizontal at the parent's center y, then
# vertical at the boss's center x. The last leg always enters the boss room
# through a specific wall — which wall depends on the parent's grid position
# relative to the boss. Door rotation 0 = vertical slab (west/east entry);
# PI/2 = horizontal slab (north/south entry via the vertical corridor leg).
func boss_corridor_entrance(boss_id: int) -> Dictionary:
	var fallback := {"position": Vector2.ZERO, "rotation": 0.0}
	if not room_positions.has(boss_id):
		return fallback

	var step := ROOM_SIZE_PX + CORRIDOR_WIDTH_PX
	var boss_grid: Vector2i = room_positions[boss_id]
	var boss_origin := Vector2(float(boss_grid.x * step), float(boss_grid.y * step))
	var boss_center := boss_origin + Vector2(ROOM_SIZE_PX / 2.0, ROOM_SIZE_PX / 2.0)

	# Find the parent room — the corridor that leads INTO the boss room.
	var parent_grid := boss_grid
	for pair in corridors:
		if pair[1] == boss_id and room_positions.has(pair[0]):
			parent_grid = room_positions[pair[0]]
			break

	if parent_grid.y == boss_grid.y:
		# Pure horizontal corridor — enters west or east wall.
		if parent_grid.x < boss_grid.x:
			return {"position": Vector2(boss_origin.x, boss_center.y), "rotation": 0.0}
		else:
			return {"position": Vector2(boss_origin.x + ROOM_SIZE_PX, boss_center.y), "rotation": 0.0}
	else:
		# L-shaped corridor — vertical leg at boss_center.x enters north or south wall.
		if parent_grid.y > boss_grid.y:
			return {"position": Vector2(boss_center.x, boss_origin.y + ROOM_SIZE_PX), "rotation": PI / 2.0}
		else:
			return {"position": Vector2(boss_center.x, boss_origin.y), "rotation": PI / 2.0}
