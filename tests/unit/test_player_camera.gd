extends GutTest

func test_player_scene_has_camera2d():
	var scene = load("res://scenes/player.tscn").instantiate()
	var camera = scene.get_node_or_null("Camera2D")
	assert_not_null(camera, "player.tscn must have a Camera2D child")
	assert_true(camera is Camera2D, "Camera2D child must be typed Camera2D")
	scene.free()

func test_player_camera_is_enabled():
	var scene = load("res://scenes/player.tscn").instantiate()
	var camera = scene.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera)
	assert_true(camera.enabled, "Camera2D must be enabled so it activates when added to the tree")
	scene.free()

func test_player_camera_is_child_of_player_for_automatic_follow():
	var scene = load("res://scenes/player.tscn").instantiate()
	var camera = scene.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera)
	assert_eq(camera.get_parent(), scene,
		"Camera2D must be a DIRECT child of Player so transform inheritance follows movement")
	scene.free()

func test_player_camera_uses_position_smoothing():
	var scene = load("res://scenes/player.tscn").instantiate()
	var camera = scene.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera)
	assert_true(camera.position_smoothing_enabled,
		"Camera2D should use position smoothing for a gentle tracking feel")
	scene.free()
