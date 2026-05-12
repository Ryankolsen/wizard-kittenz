extends GutTest

func test_enemy_scene_has_sprite2d():
	var scene = load("res://scenes/enemy.tscn").instantiate()
	var sprite = scene.get_node_or_null("Sprite2D")
	assert_not_null(sprite, "enemy.tscn must have a Sprite2D child")
	assert_true(sprite is Sprite2D, "Sprite2D child must be typed Sprite2D")
	scene.free()

func test_enemy_scene_has_no_polygon2d_placeholder():
	var scene = load("res://scenes/enemy.tscn").instantiate()
	var placeholder = scene.get_node_or_null("Placeholder")
	assert_null(placeholder, "Polygon2D placeholder must be removed from enemy.tscn")
	scene.free()

func test_slime_enemy_has_texture_after_ready():
	var scene = load("res://scenes/enemy.tscn").instantiate()
	scene.data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	add_child_autofree(scene)
	var sprite = scene.get_node_or_null("Sprite2D") as Sprite2D
	assert_not_null(sprite)
	assert_not_null(sprite.texture, "SLIME enemy must have a texture after _ready()")

func test_bat_enemy_has_texture_after_ready():
	var scene = load("res://scenes/enemy.tscn").instantiate()
	scene.data = EnemyData.make_new(EnemyData.EnemyKind.BAT)
	add_child_autofree(scene)
	var sprite = scene.get_node_or_null("Sprite2D") as Sprite2D
	assert_not_null(sprite)
	assert_not_null(sprite.texture, "BAT enemy must have a texture after _ready()")

func test_slime_and_bat_textures_differ():
	var slime = load("res://scenes/enemy.tscn").instantiate()
	slime.data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	add_child_autofree(slime)

	var bat = load("res://scenes/enemy.tscn").instantiate()
	bat.data = EnemyData.make_new(EnemyData.EnemyKind.BAT)
	add_child_autofree(bat)

	var slime_tex = (slime.get_node("Sprite2D") as Sprite2D).texture
	var bat_tex = (bat.get_node("Sprite2D") as Sprite2D).texture
	assert_ne(slime_tex, bat_tex, "SLIME and BAT must use different textures")
