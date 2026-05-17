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
