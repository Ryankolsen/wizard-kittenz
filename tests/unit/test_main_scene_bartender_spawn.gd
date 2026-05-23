extends GutTest

# Tests for the in-dungeon Bartender spawn wired into main_scene._setup_rooms
# (issue #179). Closes the gap left by the prior bar-room slices: the
# Bartender node existed in bar_room.tscn but the dungeon scene never
# instantiated one, so the player had no in-run shop access. main_scene
# now spawns a Bartender at the TYPE_BAR room's world center and binds its
# shop_requested signal to a CanvasLayer overlay host.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"


func before_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.coop_session = null
		gs.dungeon_run_controller = null
		gs.local_player_id = ""


func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.coop_session = null
		gs.dungeon_run_controller = null


func _find_bartender(node: Node) -> Bartender:
	for child in node.get_children():
		if child is Bartender:
			return child
	return null


func test_main_scene_spawns_exactly_one_bartender():
	# Every dungeon contains exactly one TYPE_BAR room (#180 invariant), so
	# the main scene must spawn exactly one Bartender. Pin that the bartender
	# exists and is unique — neither missing nor duplicated by the iteration.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	var bartenders: Array = []
	for child in inst.get_children():
		if child is Bartender:
			bartenders.append(child)
	assert_eq(bartenders.size(), 1,
		"main scene spawns exactly one Bartender for the dungeon's single bar room")


func test_bartender_positioned_at_bar_room_center():
	# The bartender's world position should match the bar room's world
	# center — that's the player-facing landmark inside the bar's tilemap
	# footprint. Compares against DungeonLayoutEngine.compute for the same
	# dungeon to avoid coupling to any hard-coded coordinate.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	var rc: DungeonRunController = get_node("/root/GameState").dungeon_run_controller
	var bar_id := -1
	for r in rc.dungeon.rooms:
		if r.type == Room.TYPE_BAR:
			bar_id = r.id
			break
	assert_true(bar_id >= 0, "dungeon must contain a bar room")

	var layout: DungeonLayout = DungeonLayoutEngine.new().compute(rc.dungeon)
	var expected: Vector2 = layout.room_center_world(bar_id)

	var bartender := _find_bartender(inst)
	assert_not_null(bartender, "bartender must be spawned")
	assert_eq(bartender.position, expected,
		"bartender sits at the bar room's world center")


func test_bartender_shop_requested_mounts_overlay():
	# End-to-end: firing the bartender's shop_requested signal mounts a
	# ShopScreen overlay under main_scene. Validates the wiring point —
	# the actual shop UI behavior is covered by ShopScreen's own tests.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	var bartender := _find_bartender(inst)
	assert_not_null(bartender, "bartender must be spawned")

	var canvas_before := 0
	for child in inst.get_children():
		if child is CanvasLayer:
			canvas_before += 1

	bartender.shop_requested.emit()

	var canvas_after := 0
	var found_shop := false
	for child in inst.get_children():
		if child is CanvasLayer:
			canvas_after += 1
			for grand in child.get_children():
				if grand is ShopScreen:
					found_shop = true
	assert_eq(canvas_after, canvas_before + 1,
		"shop_requested adds one CanvasLayer to host the overlay")
	assert_true(found_shop,
		"the new CanvasLayer hosts a ShopScreen instance")
