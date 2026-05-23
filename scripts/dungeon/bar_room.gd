class_name BarRoom
extends Node2D

# Bar-room scene root (issue #181). Hosts the warm-tavern background, two
# ExitZone doorways the player walks through to return to the dungeon, and
# an enemy barrier that keeps pursuing enemies out of the safe room.
#
# Decisions:
# - player_exited_bar is the single scene-level exit signal — both
#   ExitZone children re-emit through this one signal so callers outside
#   the bar don't need to know about per-door wiring (user story 7: "exit
#   freely via either door").
# - The enemy barrier is a script-level guard layered on top of the
#   StaticBody2D doorway walls in the .tscn. Walls block the normal
#   move_and_slide path; the Area2D + _on_enemy_barrier_body_entered
#   pushback covers the contract that enemies do not cross even if a
#   per-kind behavior teleports them (e.g., Haunted Spray Bottle floats
#   over wall tiles by clearing collision_mask — see enemy.gd:60-63).
# - Enemies are pushed away from the bar's center along the entry vector.
#   The pushback distance is enough to drop them outside the trigger area
#   on the next physics step; tuned in QA (#184) if it feels off.

signal player_exited_bar()

const ENEMY_PUSHBACK_DISTANCE: float = 64.0
const SHOP_SCENE_PATH := "res://scenes/shop_screen.tscn"

# Tile-based layout (#190). The room is a 10x8 walkable floor surrounded by
# a 1-tile wall ring, painted on _ready into the scene's TileMap node. Two
# 2-tile-tall door gaps on the left/right walls let the player reach the
# ExitZones positioned just inside the openings.
const TILE_SIZE := 16
const ROOM_W := 10
const ROOM_H := 8
const FLOOR_TEXTURE_PATH := "res://assets/sprites/floor.png"
const BAR_COUNTER_TEXTURE_PATH := "res://assets/sprites/bar_counter.png"
const TAVERN_TABLE_TEXTURE_PATH := "res://assets/sprites/tavern_table.png"

const _SOURCE_FLOOR := 0
const _SOURCE_WALL := 1

# Holds the shop overlay's CanvasLayer wrapper while open so a duplicate
# shop_requested press (mashing attack while the shop is already up) is a
# no-op rather than stacking a second screen on top.
var _shop_overlay: CanvasLayer = null


func _ready() -> void:
	_paint_room_tilemap()
	_apply_prop_textures()
	for zone in get_exit_zones():
		if not zone.player_entered.is_connected(_on_exit_zone_player_entered):
			zone.player_entered.connect(_on_exit_zone_player_entered)
	var barrier := get_node_or_null("EnemyBarrier") as Area2D
	if barrier != null and not barrier.body_entered.is_connected(_on_enemy_barrier_body_entered):
		barrier.body_entered.connect(_on_enemy_barrier_body_entered)
	var bartender := get_node_or_null("Bartender")
	if bartender != null and bartender.has_signal("shop_requested") \
			and not bartender.shop_requested.is_connected(_on_shop_requested):
		bartender.shop_requested.connect(_on_shop_requested)


# Returns the ExitZone children in the order they appear in the scene
# tree. Two zones are expected — one per visible doorway in
# bar_interior.png. Tests assert size == 2 to lock in the content
# contract; runtime wiring just iterates whatever zones exist.
func get_exit_zones() -> Array:
	var out: Array = []
	for child in get_children():
		if child is ExitZone:
			out.append(child)
	return out


func _on_exit_zone_player_entered() -> void:
	player_exited_bar.emit()


# Pushes an enemy body that crossed into the bar back outside along the
# vector from the bar's center to the body's current position. Non-enemy
# bodies (including the player) are ignored so the player can pass through
# the doorways freely.
func _on_enemy_barrier_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("enemies"):
		return
	if not (body is Node2D):
		return
	var b := body as Node2D
	var dir := (b.global_position - global_position)
	if dir.length_squared() <= 0.0:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	b.global_position += dir * ENEMY_PUSHBACK_DISTANCE


# Mounts ShopScreen as a CanvasLayer overlay so the bar room scene stays
# in the tree underneath. Overlay mode tells ShopScreen to emit
# back_pressed instead of doing its default change_scene_to_file, letting
# us tear down just the overlay and leave the player standing at the bar.
func _on_shop_requested() -> void:
	if _shop_overlay != null and is_instance_valid(_shop_overlay):
		return
	var scene: PackedScene = load(SHOP_SCENE_PATH)
	if scene == null:
		return
	var shop: ShopScreen = scene.instantiate()
	var layer := CanvasLayer.new()
	layer.add_child(shop)
	add_child(layer)
	shop.set_overlay_mode(true)
	shop.back_pressed.connect(_on_shop_closed)
	_shop_overlay = layer


func _on_shop_closed() -> void:
	if _shop_overlay != null and is_instance_valid(_shop_overlay):
		_shop_overlay.queue_free()
	_shop_overlay = null


# Loads the prop textures at runtime and assigns them to the placed Sprite2D
# nodes. Done in script (not as ext_resources in the .tscn) because the
# new prop pngs (#189) ship without .import sidecars in some checkouts; an
# ext_resource referencing a missing .import would error the whole scene
# load. ResourceLoader.exists() gates the load so a missing asset leaves
# the sprite blank rather than crashing.
func _apply_prop_textures() -> void:
	_apply_sprite_texture("BarCounter", BAR_COUNTER_TEXTURE_PATH)
	for name in ["Table1", "Table2"]:
		_apply_sprite_texture(name, TAVERN_TABLE_TEXTURE_PATH)


func _apply_sprite_texture(node_name: String, path: String) -> void:
	var sprite := get_node_or_null(node_name) as Sprite2D
	if sprite == null:
		return
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	if tex != null:
		sprite.texture = tex


# Paints the room floor + perimeter walls into the scene's TileMap. Two
# door-shaped gaps (2 cells tall) on the left and right walls give the
# ExitZones at those positions a clear physics path so the player can walk
# through. The TileSet is built programmatically so the scene file stays
# code-free; tile collision uses a single physics layer whose polygon
# covers the full tile on the wall source.
func _paint_room_tilemap() -> void:
	var tilemap := get_node_or_null("TileMap") as TileMap
	if tilemap == null:
		return
	tilemap.tile_set = _build_tileset()
	# Center the room on the BarRoom origin so the player teleport-in target
	# (which lands at the scene's origin) puts them inside the room.
	var origin := Vector2i(-ROOM_W / 2 - 1, -ROOM_H / 2 - 1)
	var door_ys: Array = [-1, 0]  # Two vertically adjacent door cells.
	for y in range(-1, ROOM_H + 1):
		for x in range(-1, ROOM_W + 1):
			var cell := Vector2i(origin.x + x + 1, origin.y + y + 1)
			var is_perimeter: bool = (
				x == -1 or x == ROOM_W or y == -1 or y == ROOM_H)
			if is_perimeter:
				# Skip wall cells that fall on a door opening; the gap stays
				# painted-floor so the player can walk through.
				if (x == -1 or x == ROOM_W) and cell.y in door_ys:
					tilemap.set_cell(0, cell, _SOURCE_FLOOR, Vector2i(0, 0))
				else:
					tilemap.set_cell(0, cell, _SOURCE_WALL, Vector2i(0, 0))
			else:
				tilemap.set_cell(0, cell, _SOURCE_FLOOR, Vector2i(0, 0))


func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	# Physics layer 0 = wall collision. Player.gd's CharacterBody2D mask is 2
	# (collision_layer bit 1 set on the wall side), so layer mask bit 1 is
	# what blocks the player.
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1 << 1)
	_add_floor_source(ts, _SOURCE_FLOOR, Color(0.55, 0.45, 0.35))
	_add_wall_source(ts, _SOURCE_WALL, Color(0.2, 0.22, 0.28))
	return ts


func _add_floor_source(ts: TileSet, source_id: int, tint: Color) -> void:
	var src := TileSetAtlasSource.new()
	src.texture = _tinted_tile_texture(tint)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, source_id)


func _add_wall_source(ts: TileSet, source_id: int, tint: Color) -> void:
	var src := TileSetAtlasSource.new()
	src.texture = _tinted_tile_texture(tint)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	src.create_tile(Vector2i(0, 0))
	# Source must be added to the TileSet first so its tile data inherits
	# the TileSet's physics-layer configuration; otherwise add_collision_polygon
	# errors with "Index p_layer_id = 0 is out of bounds".
	ts.add_source(src, source_id)
	var data: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	data.add_collision_polygon(0)
	var half: float = float(TILE_SIZE) / 2.0
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	]))


# Builds an in-memory tinted texture so the TileSet has something to draw
# even when floor.png isn't available (headless tests / minimal sandbox).
# When floor.png loads, the tint is multiplied into the sprite the same way
# the dungeon painter does — keeps the bar's visual language consistent.
func _tinted_tile_texture(tint: Color) -> Texture2D:
	var base := load(FLOOR_TEXTURE_PATH) as Texture2D
	if base == null:
		var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(tint)
		return ImageTexture.create_from_image(img)
	var img: Image = base.get_image()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != TILE_SIZE or img.get_height() != TILE_SIZE:
		img.resize(TILE_SIZE, TILE_SIZE)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	return ImageTexture.create_from_image(img)
