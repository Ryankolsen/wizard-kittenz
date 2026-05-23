extends GutTest

# Tests for the bartender NPC (issue #183). The bartender sits in the bar
# room and opens the shop when the player presses attack while in proximity.
# Tests instantiate the scene directly so the proximity + attack signal
# wiring is exercised without spinning up a player or shop overlay.

const BARTENDER_SCENE_PATH := "res://scenes/bartender.tscn"


func _make_bartender() -> Bartender:
	var npc: Bartender = load(BARTENDER_SCENE_PATH).instantiate()
	add_child_autofree(npc)
	return npc


func test_shop_requested_emits_when_in_range_and_attack_pressed():
	# Core wiring: player enters proximity, presses attack, shop opens.
	var bartender := _make_bartender()
	var emitted := [false]
	bartender.shop_requested.connect(func(): emitted[0] = true)
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	assert_true(emitted[0], "shop_requested emitted when in range and attack pressed")


func test_shop_not_requested_when_player_out_of_range():
	# Content/gating: pressing attack outside the proximity area is a no-op
	# for the bartender. Player.gd's own attack handler still fires normally.
	var bartender := _make_bartender()
	var emitted := [false]
	bartender.shop_requested.connect(func(): emitted[0] = true)
	# Do NOT call _on_player_entered_range — player has never been in range.
	bartender._on_attack_pressed()
	assert_false(emitted[0], "shop_requested not emitted when player out of range")


func test_repeated_attack_presses_emit_once_per_press():
	# Edge: each attack press while in range fires shop_requested. Two
	# discrete presses → two emits. Locks in that the gate is per-event,
	# not "first press only" — closing the shop and pressing again should
	# reopen it.
	var bartender := _make_bartender()
	var emits := [0]
	bartender.shop_requested.connect(func(): emits[0] += 1)
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	bartender._on_attack_pressed()
	assert_eq(emits[0], 2,
		"two discrete attack presses while in range emit twice")


func test_exiting_range_stops_emits():
	# Edge: after the player walks away, attack presses no longer open the
	# shop. Body_exited → _on_player_exited_range flips the gate back off.
	var bartender := _make_bartender()
	var emitted := [false]
	bartender.shop_requested.connect(func(): emitted[0] = true)
	bartender._on_player_entered_range()
	bartender._on_player_exited_range()
	bartender._on_attack_pressed()
	assert_false(emitted[0],
		"shop_requested not emitted once player has exited range")


# --- Sprite update (#191) --------------------------------------------------
# The bartender gains a Sprite2D child textured with assets/sprites/bartender.png
# (orange tabby in vest and apron). Texture is loaded at runtime to avoid a
# missing-.import sidecar erroring scene load; the resource_path on the
# loaded texture still reflects the canonical asset path.

func test_bartender_sprite_uses_bartender_png():
	var bartender := _make_bartender()
	var sprite := bartender.find_child("Sprite2D", true, false) as Sprite2D
	assert_not_null(sprite, "bartender has a Sprite2D child")
	assert_not_null(sprite.texture, "bartender sprite has a texture assigned")
	assert_eq(sprite.texture.resource_path,
		"res://assets/sprites/bartender.png",
		"Bartender uses new bartender.png sprite")


func test_bartender_lives_in_bar_room():
	var room: BarRoom = load("res://scenes/bar_room.tscn").instantiate()
	add_child_autofree(room)
	var bartender := room.find_child("Bartender", true, false)
	assert_not_null(bartender, "bar room contains a Bartender node")


func test_bartender_positioned_behind_bar_counter():
	# Y-sort relationship: bartender stands behind the counter (smaller y →
	# drawn before the counter so the counter overlaps from the front).
	var room: BarRoom = load("res://scenes/bar_room.tscn").instantiate()
	add_child_autofree(room)
	var bartender := room.find_child("Bartender", true, false) as Node2D
	var counter := room.find_child("BarCounter", true, false) as Node2D
	assert_not_null(bartender, "bartender exists")
	assert_not_null(counter, "counter exists")
	assert_lt(bartender.position.y, counter.position.y,
		"bartender sits behind (smaller y than) the bar counter for y-sort")
