extends GutTest

# Tests for the ExitDoor scene (issue #98). The door is the boss-room exit:
# starts locked (blocking StaticBody collision + closed visual), transitions
# to open when boss_room_cleared fires, and emits player_exited_dungeon
# when the player's body enters its trigger area while unlocked. These tests
# instantiate the scene directly so the wire is exercised end-to-end without
# requiring a full main_scene around it.

const EXIT_DOOR_SCENE_PATH := "res://scenes/exit_door.tscn"

func _make_door() -> ExitDoor:
	var door: ExitDoor = load(EXIT_DOOR_SCENE_PATH).instantiate()
	add_child_autofree(door)
	return door

func test_starts_locked_with_active_collision():
	var door := _make_door()
	assert_true(door.is_locked, "door starts locked")
	var coll := door.get_node("CollisionShape2D") as CollisionShape2D
	assert_not_null(coll, "blocking CollisionShape2D must exist at root")
	assert_false(coll.disabled,
		"collision must be active so the player can't walk through pre-clear")

func test_open_unlocks_and_disables_collision():
	# Issue #98 AC: boss_room_cleared -> door.open() -> collision disabled.
	var door := _make_door()
	door.open()
	assert_false(door.is_locked, "door is unlocked after open()")
	var coll := door.get_node("CollisionShape2D") as CollisionShape2D
	assert_true(coll.disabled,
		"collision disabled after open so the player can walk through")

func test_open_is_idempotent():
	# A repeat open() is a safe no-op so the wire layer doesn't have to
	# dedupe boss_room_cleared re-fires (same idempotency contract as
	# DungeonRunController.mark_room_cleared).
	var door := _make_door()
	door.open()
	door.open()
	assert_false(door.is_locked)

func test_emits_player_exited_dungeon_when_open():
	var door := _make_door()
	door.open()
	watch_signals(door)
	door._on_trigger_body_entered(autofree(Node.new()))
	assert_signal_emit_count(door, "player_exited_dungeon", 1,
		"open door fires player_exited_dungeon on body entering trigger")

func test_does_not_emit_while_locked():
	# Defensive: even if the trigger Area2D somehow detects a body while
	# the door is still locked, the exit signal must not fire. In normal
	# play the blocking StaticBody collision prevents entry entirely, but
	# the gate makes the contract explicit.
	var door := _make_door()
	watch_signals(door)
	door._on_trigger_body_entered(autofree(Node.new()))
	assert_signal_emit_count(door, "player_exited_dungeon", 0,
		"locked door does not fire player_exited_dungeon")

func test_visual_swaps_on_open():
	# Locked visual hides and open visual shows after open() — closes the
	# user story "killing the boss causes the exit door to visually open."
	var door := _make_door()
	var locked_v := door.get_node("LockedVisual") as CanvasItem
	var open_v := door.get_node("OpenVisual") as CanvasItem
	assert_true(locked_v.visible, "locked visual shown pre-open")
	assert_false(open_v.visible, "open visual hidden pre-open")
	door.open()
	assert_false(locked_v.visible, "locked visual hidden post-open")
	assert_true(open_v.visible, "open visual shown post-open")
