extends GutTest

const NEW_KINDS := [
	EnemyData.EnemyKind.ANGRY_PIGEON,
	EnemyData.EnemyKind.ROGUE_ROOMBA,
	EnemyData.EnemyKind.DOG_KNIGHT,
	EnemyData.EnemyKind.CATNIP_DEALER,
	EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE,
]

func _spawn(kind: int, is_boss: bool = false) -> Node:
	var scene = load("res://scenes/enemy.tscn").instantiate()
	scene.data = EnemyData.make_new(kind)
	scene.data.is_boss = is_boss
	add_child_autofree(scene)
	return scene

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

func test_every_new_kind_loads_a_texture():
	for kind in NEW_KINDS:
		var enemy = _spawn(kind)
		var sprite := enemy.get_node("Sprite2D") as Sprite2D
		assert_not_null(sprite.texture,
			"kind %d must have a texture after _ready()" % kind)

func test_all_new_kinds_have_distinct_textures():
	var seen := {}
	for kind in NEW_KINDS:
		var enemy = _spawn(kind)
		var tex = (enemy.get_node("Sprite2D") as Sprite2D).texture
		assert_false(seen.has(tex),
			"kind %d must use a unique texture" % kind)
		seen[tex] = true
	assert_eq(seen.size(), NEW_KINDS.size(),
		"all 5 new kinds must load distinct texture resources")

func test_boss_texture_override():
	var boss = _spawn(EnemyData.EnemyKind.DOG_KNIGHT, true)
	var tex = (boss.get_node("Sprite2D") as Sprite2D).texture
	assert_not_null(tex)
	assert_true(tex.resource_path.find("vacuum_boss") != -1,
		"boss enemy must load vacuum_boss texture regardless of kind")

func test_no_kind_uses_old_placeholder_sprites():
	for kind in NEW_KINDS:
		var enemy = _spawn(kind)
		var tex = (enemy.get_node("Sprite2D") as Sprite2D).texture
		var path := tex.resource_path
		assert_true(path.find("slime") == -1,
			"kind %d texture path must not contain 'slime' (was %s)" % [kind, path])
		assert_true(path.find("bat") == -1,
			"kind %d texture path must not contain 'bat' (was %s)" % [kind, path])
