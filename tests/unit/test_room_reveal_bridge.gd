extends GutTest

# RoomRevealBridge wires DungeonRunController.current_room_changed into
# FloorMapState.mark_revealed. On bind(), the start room is pre-revealed
# so the minimap shows the player's origin before any movement.

func _make_dungeon() -> Dungeon:
	var d := Dungeon.new()
	var s := Room.make(0, Room.TYPE_START)
	var a := Room.make(1, Room.TYPE_STANDARD)
	var b := Room.make(2, Room.TYPE_STANDARD)
	s.connections = [1, 2]
	d.add_room(s)
	d.add_room(a)
	d.add_room(b)
	d.start_id = 0
	d.boss_id = 2
	return d

func test_bind_prereveals_start_room():
	var d := _make_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	var state := FloorMapState.new()
	var bridge := RoomRevealBridge.new()
	bridge.bind(c, state)
	assert_true(state.is_revealed(0), "start room revealed on bind")

func test_current_room_change_marks_revealed():
	var d := _make_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	var state := FloorMapState.new()
	var bridge := RoomRevealBridge.new()
	bridge.bind(c, state)
	c.enter_room(1)
	assert_true(state.is_revealed(0), "start still revealed")
	assert_true(state.is_revealed(1), "entered room marked revealed")

func test_repeat_enter_is_idempotent():
	# Walking back into the start room (or any revealed room) must not
	# inflate the set — mark_revealed is idempotent and the bridge does
	# not need to dedupe upstream.
	var d := _make_dungeon()
	var c := DungeonRunController.new()
	c.start(d)
	var state := FloorMapState.new()
	var bridge := RoomRevealBridge.new()
	bridge.bind(c, state)
	c.enter_room(1)
	c.enter_room(1)
	assert_eq(state.revealed_ids().size(), 2)
