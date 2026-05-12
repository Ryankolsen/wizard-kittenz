class_name DungeonFloor
extends RefCounted

const FLOOR_TEXTURE_PATH := "res://assets/sprites/floor.png"
const TILE_SIZE := 16

# Paints a solid stone floor on `tilemap` covering the given pixel dimensions.
# Creates the TileSet programmatically so no .tres resource file is needed.
static func paint(tilemap: TileMap, width_px: int = 480, height_px: int = 270) -> void:
	if tilemap == null:
		return
	var texture := load(FLOOR_TEXTURE_PATH) as Texture2D
	if texture == null:
		return
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.create_tile(Vector2i(0, 0))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, 0)
	tilemap.tile_set = tile_set
	var cols := ceili(float(width_px) / TILE_SIZE)
	var rows := ceili(float(height_px) / TILE_SIZE)
	for y in range(rows):
		for x in range(cols):
			tilemap.set_cell(0, Vector2i(x, y), 0, Vector2i(0, 0))
