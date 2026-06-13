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
const BOSS_ROOM_SIZE_PX: int = 384
const CORRIDOR_WIDTH_PX: int = 80
# Must match DungeonTilemapPainter.TILE_SIZE. Half this value centres the
# door on the actual pixel centre of the corridor tiles — room_center_world
# returns the tile-origin (tile * 16) not the tile-centre (tile * 16 + 8).
const TILE_SIZE_PX: int = 16

var room_positions: Dictionary = {}
var corridors: Array = []
var boss_id: int = -1

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
	var room_size := BOSS_ROOM_SIZE_PX if room_id == boss_id else ROOM_SIZE_PX
	var origin := grid_to_world(room_positions[room_id], ROOM_SIZE_PX, CORRIDOR_WIDTH_PX)
	return origin + Vector2(room_size / 2, room_size / 2)

# World-space bounding rect of any room (standard or boss). Used by the spawn-
# position spreader to fan out multi-mob rooms (#372) — origin is the top-left
# pixel of the floor area, size is the room's pixel dimensions. Returns an
# empty Rect2 for unknown room ids (mirrors room_center_world's sentinel).
func room_rect_world(room_id: int) -> Rect2:
	if not room_positions.has(room_id):
		return Rect2()
	var room_size: int = BOSS_ROOM_SIZE_PX if room_id == boss_id else ROOM_SIZE_PX
	var origin: Vector2 = grid_to_world(room_positions[room_id], ROOM_SIZE_PX, CORRIDOR_WIDTH_PX)
	return Rect2(origin, Vector2(room_size, room_size))

# World position and rotation for the exit door on the boss room's south wall.
# The corridor always enters from the north (layout engine invariant), so the
# exit door lives on the opposite south wall — the player enters freely, kills
# the boss, then the south door unlocks. Returns {"position": Vector2, "rotation": float}.
func boss_exit_position(boss_id: int) -> Dictionary:
	if not room_positions.has(boss_id):
		return {"position": Vector2.ZERO, "rotation": 0.0}

	var step := ROOM_SIZE_PX + CORRIDOR_WIDTH_PX
	var half_tile := TILE_SIZE_PX / 2
	var boss_grid: Vector2i = room_positions[boss_id]
	var boss_origin := Vector2(float(boss_grid.x * step), float(boss_grid.y * step))
	var room_center_x := boss_origin.x + BOSS_ROOM_SIZE_PX / 2.0 + half_tile
	# South wall: last tile row of the boss room floor.
	return {
		"position": Vector2(room_center_x, boss_origin.y + BOSS_ROOM_SIZE_PX - half_tile),
		"rotation": PI / 2.0
	}

# World-space bounding rect of the boss room floor. Used by RoomSpawnPlanner to
# set EnemyData.room_bounds so the enemy node can clamp the boss's position
# each physics frame (keeps the boss from wandering into corridors / other rooms).
func boss_room_bounds(boss_room_id: int) -> Rect2:
	if not room_positions.has(boss_room_id):
		return Rect2()
	var step: int = ROOM_SIZE_PX + CORRIDOR_WIDTH_PX
	var grid: Vector2i = room_positions[boss_room_id]
	var origin := Vector2(float(grid.x * step), float(grid.y * step))
	return Rect2(origin, Vector2(BOSS_ROOM_SIZE_PX, BOSS_ROOM_SIZE_PX))
