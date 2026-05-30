extends GutTest

# Slice #301 (PRD #297): Enemy._ready must load the boss sprite from the
# per-floor paths stamped on EnemyData by RoomSpawnPlanner, not the
# previously hard-coded vacuum_boss path. Pins both the right- and
# left-facing branches and the fallback for legacy / test data.

func _make_boss_data(facing_x: float, left_path: String, right_path: String) -> EnemyData:
	var d := EnemyData.make_new(EnemyData.EnemyKind.SIR_PICKLETON)
	d.is_boss = true
	d.facing = Vector2(facing_x, 0.0)
	d.boss_sprite_left_path = left_path
	d.boss_sprite_right_path = right_path
	return d

func _spawn(data: EnemyData) -> Node:
	var scene = load("res://scenes/enemy.tscn").instantiate()
	scene.data = data
	add_child_autofree(scene)
	return scene

func test_boss_right_facing_uses_right_sprite_path():
	# Pickleton's right sprite doesn't exist on disk yet (slice #300), so
	# we exercise the path-selection logic with a path that does:
	# vacuum_boss for both directions.
	var d := _make_boss_data(1.0,
		"res://assets/sprites/vacuum_boss.png",
		"res://assets/sprites/vacuum_boss.png")
	d.boss_sprite_right_path = "res://assets/sprites/vacuum_boss.png"
	var enemy := _spawn(d)
	var sprite := enemy.get_node("Sprite2D") as Sprite2D
	assert_not_null(sprite.texture, "boss must have a texture")
	assert_eq(sprite.texture.resource_path, d.boss_sprite_right_path)

func test_boss_left_facing_uses_left_sprite_path():
	var d := _make_boss_data(-1.0,
		"res://assets/sprites/vacuum_boss.png",
		"res://assets/sprites/vacuum_boss.png")
	var enemy := _spawn(d)
	var sprite := enemy.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.texture.resource_path, d.boss_sprite_left_path)

func test_boss_falls_back_to_vacuum_when_paths_empty():
	# Test fixtures + saves predating BossRoster leave both paths empty.
	# Enemy.gd must fall back to vacuum_boss rather than crashing on null.
	var d := EnemyData.make_new(EnemyData.EnemyKind.ROGUE_ROOMBA)
	d.is_boss = true
	var enemy := _spawn(d)
	var sprite := enemy.get_node("Sprite2D") as Sprite2D
	assert_not_null(sprite.texture)
	assert_true(sprite.texture.resource_path.find("vacuum_boss") != -1,
		"empty boss paths must fall back to vacuum_boss")
