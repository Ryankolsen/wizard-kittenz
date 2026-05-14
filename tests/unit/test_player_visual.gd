extends GutTest

func test_player_scene_has_sprite2d():
	var scene = load("res://scenes/player.tscn").instantiate()
	var sprite = scene.get_node_or_null("Sprite2D")
	assert_not_null(sprite, "player.tscn must have a Sprite2D child")
	assert_true(sprite is Sprite2D, "Sprite2D child must be typed Sprite2D")
	scene.free()

func test_player_scene_has_no_polygon2d_placeholder():
	var scene = load("res://scenes/player.tscn").instantiate()
	var placeholder = scene.get_node_or_null("Placeholder")
	assert_null(placeholder, "Polygon2D placeholder must be removed from player.tscn")
	scene.free()

func test_player_sprite_has_texture_after_ready():
	var scene = load("res://scenes/player.tscn").instantiate()
	add_child_autofree(scene)
	var sprite = scene.get_node_or_null("Sprite2D") as Sprite2D
	assert_not_null(sprite)
	assert_not_null(sprite.texture, "Sprite2D must have a non-null texture after _ready()")

func test_main_scene_has_tilemap():
	var scene = load("res://scenes/main.tscn").instantiate()
	var tilemap = scene.get_node_or_null("TileMap")
	assert_not_null(tilemap, "main.tscn must have a TileMap node")
	assert_true(tilemap is TileMap, "TileMap node must be typed TileMap")
	scene.free()

