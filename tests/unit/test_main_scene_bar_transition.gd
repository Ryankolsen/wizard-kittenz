extends GutTest

# Tests for the bar-entrance scene swap wired into main_scene (issue #187).
# Walking the player onto a bar_entrance_tile mounts bar_room.tscn as a child
# of main_scene; the bar's player_exited_bar signal tears the overlay down
# and returns the player to the entrance tile in the dungeon. HP, MP, and
# currency live on long-lived state (CharacterData / CurrencyLedger) that
# the transition never touches, so the round-trip is value-preserving by
# construction — locked in by an explicit before/after assert.

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


func _find_child_of_type(node: Node, klass) -> Node:
	for child in node.get_children():
		if is_instance_of(child, klass):
			return child
	return null


func test_no_bartender_spawned_directly_under_main_scene():
	# The tracer-bullet from #179 instanced a Bartender as a direct child of
	# main_scene so the in-dungeon room had shop access without a scene swap.
	# Now that bar_room.tscn hosts its own Bartender, the duplicate spawn must
	# be removed — otherwise the player would see two bartenders (one in the
	# dungeon tilemap room, one inside the bar interior).
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	for child in inst.get_children():
		assert_false(child is Bartender,
			"no Bartender lives directly under main_scene; the bar's bartender is inside bar_room.tscn")


func test_stepping_onto_bar_entrance_tile_mounts_bar_room():
	# Core wiring: when the player's tile position matches a bar_entrance_tile,
	# main_scene's _process detector mounts bar_room.tscn as a "BarRoomScene"
	# child. Tile-based detection (not body_entered) keeps the test
	# deterministic with one process_frame await.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	assert_not_null(inst._tilemap_painter, "painter must be exposed for the detector")
	assert_gt(inst._tilemap_painter.bar_entrance_tiles.size(), 0,
		"painter must have at least one entrance tile")
	var entrance_cell: Vector2i = inst._tilemap_painter.bar_entrance_tiles[0]
	inst._player.global_position = inst._tilemap.map_to_local(entrance_cell)
	await get_tree().process_frame

	assert_not_null(inst.get_node_or_null("BarRoomScene"),
		"bar room scene mounted when player steps onto an entrance tile")


func test_exit_zone_signal_returns_player_to_dungeon():
	# Content detail: firing the bar's player_exited_bar signal tears the
	# BarRoomScene down and restores the player to the dungeon-side entrance
	# tile. The restored position is the position the player was at on entry
	# (i.e., the entrance tile itself) — well within the AC's "within 1 tile"
	# tolerance.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	var entrance_cell: Vector2i = inst._tilemap_painter.bar_entrance_tiles[0]
	var entrance_world: Vector2 = inst._tilemap.map_to_local(entrance_cell)
	inst._player.global_position = entrance_world
	await get_tree().process_frame

	var bar = inst.get_node_or_null("BarRoomScene")
	assert_not_null(bar, "precondition: bar mounted")
	bar.player_exited_bar.emit()
	await get_tree().process_frame

	assert_null(inst.get_node_or_null("BarRoomScene"),
		"bar scene freed once the player exits via an ExitZone")
	assert_almost_eq(inst._player.global_position.x, entrance_world.x, 16.0,
		"player restored within one tile of the entrance, x-axis")
	assert_almost_eq(inst._player.global_position.y, entrance_world.y, 16.0,
		"player restored within one tile of the entrance, y-axis")


func test_player_state_preserved_across_round_trip():
	# Edge case: HP / MP / currency / killed-enemy state must survive the
	# enter -> exit round trip. Long-lived state lives on GameState
	# autoloads that the transition never touches, so the round-trip is
	# inherently lossless — this test pins that contract so future
	# refactors don't accidentally clear character or ledger state on
	# scene mount/unmount.
	var gs := get_node("/root/GameState")
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	var character: CharacterData = gs.current_character
	var hp_before: int = -1
	var mp_before: int = -1
	if character != null:
		hp_before = int(character.hp)
		if "mp" in character:
			mp_before = int(character.mp)
	var gold_before: int = 0
	if gs.currency_ledger != null:
		gold_before = int(gs.currency_ledger.balance(CurrencyLedger.Currency.GOLD))
	var cleared_before: Array = inst._run_controller.cleared_ids().duplicate()

	var entrance_cell: Vector2i = inst._tilemap_painter.bar_entrance_tiles[0]
	inst._player.global_position = inst._tilemap.map_to_local(entrance_cell)
	await get_tree().process_frame
	var bar = inst.get_node_or_null("BarRoomScene")
	assert_not_null(bar, "precondition: bar mounted")
	bar.player_exited_bar.emit()
	await get_tree().process_frame

	if character != null:
		assert_eq(int(character.hp), hp_before, "HP preserved across bar round-trip")
		if "mp" in character:
			assert_eq(int(character.mp), mp_before, "MP preserved across bar round-trip")
	if gs.currency_ledger != null:
		assert_eq(int(gs.currency_ledger.balance(CurrencyLedger.Currency.GOLD)),
			gold_before, "gold preserved across bar round-trip")
	assert_eq(inst._run_controller.cleared_ids(), cleared_before,
		"killed-enemy / room-clear state preserved across bar round-trip")


func test_bar_room_mounts_without_extreme_offset():
	# Issue #192: with the tile-based bar room (#190), the bar scene is
	# self-contained and no longer needs to be parked at (-50000, -50000) to
	# avoid colliding with the dungeon. Mounting near the player's current
	# dungeon position keeps the bar inside the dungeon camera-limit rect, so
	# we can drop the lift/restore camera-limit dance entirely.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	var entrance_cell: Vector2i = inst._tilemap_painter.bar_entrance_tiles[0]
	inst._player.global_position = inst._tilemap.map_to_local(entrance_cell)
	await get_tree().process_frame

	var bar = inst.get_node_or_null("BarRoomScene")
	assert_not_null(bar, "precondition: bar mounted")
	assert_lt(abs(bar.global_position.x), 10000.0,
		"bar room not at extreme x offset — old BAR_OVERLAY_OFFSET hack gone")
	assert_lt(abs(bar.global_position.y), 10000.0,
		"bar room not at extreme y offset")


func test_camera_limits_not_mutated_by_bar_entry():
	# Issue #192: _lift_camera_limits / _restore_camera_limits / _saved_camera_limits
	# are gone. Camera clamps set by _paint_dungeon (apply_camera_limits) must
	# survive a bar entry untouched — the bar is mounted inside the dungeon's
	# clamp rect so no lifting is needed.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	var camera: Camera2D = inst._player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera, "precondition: player has a Camera2D")
	var limits_before := {
		"left": camera.limit_left,
		"top": camera.limit_top,
		"right": camera.limit_right,
		"bottom": camera.limit_bottom,
	}

	var entrance_cell: Vector2i = inst._tilemap_painter.bar_entrance_tiles[0]
	inst._player.global_position = inst._tilemap.map_to_local(entrance_cell)
	await get_tree().process_frame

	assert_not_null(inst.get_node_or_null("BarRoomScene"),
		"precondition: bar mounted")
	assert_eq(camera.limit_left, limits_before["left"],
		"camera.limit_left untouched by bar entry")
	assert_eq(camera.limit_top, limits_before["top"],
		"camera.limit_top untouched by bar entry")
	assert_eq(camera.limit_right, limits_before["right"],
		"camera.limit_right untouched by bar entry")
	assert_eq(camera.limit_bottom, limits_before["bottom"],
		"camera.limit_bottom untouched by bar entry")


func test_bar_room_mounted_before_player_in_child_order():
	# Without an explicit reorder, add_child appends BarRoomScene AFTER the
	# Player sibling, and main_scene has no y_sort on its root — so the bar's
	# subtree draws on top of the player sprite in scene-tree order. The
	# _enter_bar_room handler calls move_child(bar, 0) right after add_child
	# to push the bar to the front, restoring the player's "on top of
	# everything" rendering. Asserting child index pins that move.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	var entrance_cell: Vector2i = inst._tilemap_painter.bar_entrance_tiles[0]
	inst._player.global_position = inst._tilemap.map_to_local(entrance_cell)
	await get_tree().process_frame

	var bar := inst.get_node_or_null("BarRoomScene")
	var player := inst.get_node_or_null("Player")
	assert_not_null(bar, "precondition: bar mounted")
	assert_not_null(player, "precondition: player exists under main_scene")
	assert_lt(bar.get_index(), player.get_index(),
		"bar mounted at lower child index than player so player draws on top")


func test_held_move_input_released_on_bar_entry():
	# Mobile-deploy bug: the player walks onto the bar entrance while holding a
	# movement input (a held key, or a virtual-joystick direction held still).
	# The detector mounts the bar but the input stays pressed, so the next
	# physics frame's Input.get_vector still returns that direction and the
	# kitten runs off endlessly inside the bar. _enter_bar_room must release the
	# move actions so the player stands still on entry.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	var entrance_cell: Vector2i = inst._tilemap_painter.bar_entrance_tiles[0]
	Input.action_press("move_right")
	assert_true(Input.is_action_pressed("move_right"),
		"precondition: a move action is held as the player enters")
	inst._player.global_position = inst._tilemap.map_to_local(entrance_cell)
	await get_tree().process_frame

	assert_not_null(inst.get_node_or_null("BarRoomScene"), "precondition: bar mounted")
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		assert_false(Input.is_action_pressed(action),
			"%s released on bar entry so the player doesn't keep moving" % action)
	# Defensive cleanup so a leaked press can't bleed into another test.
	Input.action_release("move_right")


func test_saved_camera_limits_field_removed():
	# Lock the refactor in: the _saved_camera_limits field that backed the
	# old lift/restore is gone, along with the lift/restore methods. Reading
	# them via the "in" operator (or has_method) lets the test fail loudly
	# if a future change reintroduces the hack.
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	assert_false("_saved_camera_limits" in inst,
		"_saved_camera_limits field removed in #192")
	assert_false(inst.has_method("_lift_camera_limits"),
		"_lift_camera_limits method removed in #192")
	assert_false(inst.has_method("_restore_camera_limits"),
		"_restore_camera_limits method removed in #192")
