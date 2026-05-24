extends GutTest

# Tests for the bar room scene (issue #181). The bar is the safe mid-dungeon
# room: two doorway ExitZones return the player to the dungeon, and an
# EnemyBarrier guards against enemies crossing into the room. Tests
# instantiate the scene directly so the wire is exercised without spinning
# up a full dungeon around it.

const BAR_ROOM_SCENE_PATH := "res://scenes/bar_room.tscn"


func _make_bar() -> BarRoom:
	var bar: BarRoom = load(BAR_ROOM_SCENE_PATH).instantiate()
	add_child_autofree(bar)
	return bar


func _make_player_body() -> Node2D:
	# Lightweight stand-in for the real Player.gd CharacterBody2D. The
	# ExitZone filters on the "players" group tag (Player.gd:59 adds it),
	# so any Node2D with that group tag exercises the same code path.
	var body := CharacterBody2D.new()
	body.add_to_group("players")
	add_child_autofree(body)
	return body


func _make_enemy_body(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var body := CharacterBody2D.new()
	body.add_to_group("enemies")
	body.global_position = pos
	add_child_autofree(body)
	return body


func test_scene_has_exactly_two_exit_zones():
	# AC: "Two ExitZone nodes exist, one per door."
	var bar := _make_bar()
	var zones := bar.get_exit_zones()
	assert_eq(zones.size(), 2, "bar room has exactly two exit zones")


func test_exit_zone_emits_player_exited_bar_on_player_entry():
	# Core wiring: an ExitZone fires its own player_entered signal, which
	# the BarRoom re-emits through scene-level player_exited_bar.
	var bar := _make_bar()
	watch_signals(bar)
	var zones := bar.get_exit_zones()
	var player := _make_player_body()
	(zones[0] as ExitZone)._on_body_entered(player)
	assert_signal_emit_count(bar, "player_exited_bar", 1,
		"first exit zone fires the scene-level exit signal")


func test_both_doors_emit_same_signal():
	# Edge case: exiting through left door or right door both emit
	# player_exited_bar (user story 7 — exit freely via either door).
	var bar := _make_bar()
	watch_signals(bar)
	var zones := bar.get_exit_zones()
	var player := _make_player_body()
	(zones[0] as ExitZone)._on_body_entered(player)
	(zones[1] as ExitZone)._on_body_entered(player)
	assert_signal_emit_count(bar, "player_exited_bar", 2,
		"both doors emit the same player_exited_bar signal")


func test_exit_zone_ignores_non_player_bodies():
	# Defensive: only bodies in the "players" group trip the zone, so
	# enemies wandering near a door don't accidentally fire the exit
	# signal (would otherwise teleport the player out of their own bar).
	var bar := _make_bar()
	watch_signals(bar)
	var zones := bar.get_exit_zones()
	var enemy := _make_enemy_body()
	(zones[0] as ExitZone)._on_body_entered(enemy)
	assert_signal_emit_count(bar, "player_exited_bar", 0,
		"non-player bodies do not emit player_exited_bar")


func test_enemy_barrier_pushes_enemy_back_outside():
	# AC: "Enemy nodes cannot cross the room boundary." Body enters at a
	# point inside the bar; the barrier handler displaces it along the
	# outward vector by ENEMY_PUSHBACK_DISTANCE. Test asserts the enemy
	# moved away from the bar center — exact distance is a tuning knob
	# (#184 QA), so we assert direction and minimum displacement.
	var bar := _make_bar()
	var enemy := _make_enemy_body(Vector2(50, 0))
	var before := enemy.global_position
	bar._on_enemy_barrier_body_entered(enemy)
	var after := enemy.global_position
	assert_true(after.x > before.x,
		"enemy pushed outward along +x (was right of bar center)")
	assert_almost_eq(after.y, before.y, 0.001,
		"enemy pushback preserves the y component when entry is purely +x")


func test_enemy_barrier_ignores_player_body():
	# AC: "Player can enter and exit through either door freely." The
	# script-level guard must not push the player back when they walk
	# into the bar — they're supposed to be in there.
	var bar := _make_bar()
	var player := _make_player_body()
	player.global_position = Vector2(50, 0)
	var before := player.global_position
	bar._on_enemy_barrier_body_entered(player)
	assert_eq(player.global_position, before,
		"player is not displaced by the enemy barrier")


func test_enemy_at_bar_center_still_gets_pushed():
	# Defensive edge: an enemy that spawns exactly at the bar center has
	# a zero outward vector. The handler falls back to a fixed direction
	# so the pushback still happens (no NaN, no zero displacement).
	var bar := _make_bar()
	var enemy := _make_enemy_body(Vector2.ZERO)
	bar._on_enemy_barrier_body_entered(enemy)
	assert_ne(enemy.global_position, Vector2.ZERO,
		"enemy at bar center still gets pushed via fallback direction")


# --- Tile-based rebuild (#190) ---------------------------------------------
# The bar room is no longer a 1280x720 raster background overlay; it's a
# proper tile-based scene with floor + wall tiles, standalone prop sprites
# (counter, tables), and visible doorways. The tests below pin the new
# content contract: TileMap node present, props named for the test's
# find_child queries, wall tiles carry collision, and the old TextureRect
# / raster background is gone so callers don't accidentally depend on it.

func test_bar_room_has_tilemap_node():
	var bar := _make_bar()
	var tilemap := bar.find_child("TileMap", true, false)
	assert_not_null(tilemap, "bar room has a TileMap node")
	assert_true(tilemap is TileMap, "TileMap child is a TileMap instance")


func test_bar_room_has_bar_counter_sprite():
	var bar := _make_bar()
	var counter := bar.find_child("BarCounter", true, false)
	assert_not_null(counter, "bar room has a BarCounter sprite")


func test_bar_room_has_at_least_two_tables():
	var bar := _make_bar()
	var tables := bar.find_children("Table*", "", true, false)
	assert_gte(tables.size(), 2, "bar room has at least 2 tables")


func test_bar_room_tilemap_has_wall_collision():
	# Wall tiles block movement: the wall atlas source must register at
	# least one physics layer in its TileSet, otherwise a KinematicBody2D
	# would walk straight through wall cells. Asserting tileset metadata
	# (not actual physics step) keeps the test deterministic in headless.
	var bar := _make_bar()
	var tilemap: TileMap = bar.find_child("TileMap", true, false)
	assert_not_null(tilemap.tile_set, "TileMap has a TileSet")
	assert_gt(tilemap.tile_set.get_physics_layers_count(), 0,
		"TileSet has at least one physics layer for wall collision")


func test_bar_room_has_no_texturerect_background():
	# Old raster-background implementation parented a Sprite2D/TextureRect
	# at 1280x720. The tile-based rebuild removes both — no node may be
	# TextureRect anywhere in the bar scene.
	var bar := _make_bar()
	var rects := bar.find_children("*", "TextureRect", true, false)
	assert_eq(rects.size(), 0,
		"no TextureRect children remain from the raster-background implementation")


func test_bar_room_tilemap_renders_below_props():
	# Y-sort on the BarRoom root sorts children by Y position. The TileMap
	# node sits at y=0 while Bartender (y=-64) and BarCounter (y=-48) are
	# above it — without a z_index override, the tilemap would draw AFTER
	# the props and cover them. z_index = -1 on the TileMap pushes the
	# floor + walls into a lower z-group, matching the dungeon's main.tscn
	# pattern, so props always sit on top of the floor.
	var bar := _make_bar()
	var tilemap: TileMap = bar.find_child("TileMap", true, false)
	assert_eq(tilemap.z_index, -1,
		"bar TileMap has z_index = -1 so floor/walls draw below props")


func test_bar_room_root_y_sorts_props_with_player():
	# Y-sort on the root: standalone props (counter, tables, bartender) and
	# the player draw in walk-behind order. The Node2D y_sort_enabled flag
	# is what enables it — pin it so the scene doesn't silently regress.
	var bar := _make_bar()
	assert_true(bar.y_sort_enabled,
		"bar root has y_sort_enabled so props layer correctly with player")


# --- Shop overlay modality (#232) ------------------------------------------
# The shop overlay must absorb GUI input — otherwise clicks bleed through to
# the HUD beneath (most visibly: Buy presses hit the Character menu button).
# The contract: a full-rect scrim Control with MOUSE_FILTER_STOP lives under
# the shop's CanvasLayer wrapper, is removed on close, and is not stacked on
# reopen.

func _find_scrim_in_overlay(overlay: CanvasLayer) -> Control:
	# The scrim is a full-rect Control sibling of (or above) the ShopScreen
	# whose mouse_filter is MOUSE_FILTER_STOP. Walk only the overlay's own
	# subtree so the ShopScreen root (also a Control) doesn't get mistaken
	# for the scrim — the scrim's defining trait is anchor-fill + STOP.
	for child in overlay.get_children():
		if child is Control and (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP \
				and (child as Control).anchor_right == 1.0 \
				and (child as Control).anchor_bottom == 1.0:
			return child
	return null


func test_shop_overlay_has_full_rect_scrim_with_mouse_filter_stop():
	# AC: clicks under the shop must be absorbed. The scrim Control filling
	# the screen with MOUSE_FILTER_STOP is the contractual hook — it sits
	# under the shop so any click that misses a shop widget still doesn't
	# bleed through to the HUD beneath.
	var bar := _make_bar()
	bar._on_shop_requested()
	var overlay := bar._shop_overlay
	assert_not_null(overlay, "shop overlay CanvasLayer was spawned")
	var scrim := _find_scrim_in_overlay(overlay)
	assert_not_null(scrim,
		"overlay has a full-rect Control scrim with MOUSE_FILTER_STOP")


func test_shop_overlay_teardown_removes_scrim() -> void:
	# AC: Back restores HUD input. The scrim (and the whole overlay) must be
	# gone from the bar's children — no leftover input-eater hanging around.
	var bar := _make_bar()
	bar._on_shop_requested()
	var shop: ShopScreen = bar._shop_overlay.get_child(bar._shop_overlay.get_child_count() - 1)
	# Find the actual ShopScreen in the overlay (scrim may come first).
	for child in bar._shop_overlay.get_children():
		if child is ShopScreen:
			shop = child
			break
	shop.back_pressed.emit()
	assert_null(bar._shop_overlay,
		"_shop_overlay is cleared after back press")
	# queue_free is deferred — wait a frame so the CanvasLayer is actually gone.
	await get_tree().process_frame
	await get_tree().process_frame
	for child in bar.get_children():
		assert_false(child is CanvasLayer,
			"no leftover CanvasLayer scrim hanging around after close")


func test_shop_overlay_reopen_does_not_stack() -> void:
	# AC: opening, closing, then reopening produces exactly one overlay and
	# one scrim — not two stacked modals each eating input independently.
	var bar := _make_bar()
	bar._on_shop_requested()
	var first_overlay := bar._shop_overlay
	var shop: ShopScreen = null
	for child in first_overlay.get_children():
		if child is ShopScreen:
			shop = child
			break
	shop.back_pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	bar._on_shop_requested()
	var canvas_layers: Array = []
	for child in bar.get_children():
		if child is CanvasLayer:
			canvas_layers.append(child)
	assert_eq(canvas_layers.size(), 1,
		"exactly one CanvasLayer overlay after open/close/open")
	var scrim := _find_scrim_in_overlay(bar._shop_overlay)
	assert_not_null(scrim, "reopened overlay still has its scrim")
