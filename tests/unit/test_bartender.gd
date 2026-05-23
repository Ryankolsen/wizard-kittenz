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
