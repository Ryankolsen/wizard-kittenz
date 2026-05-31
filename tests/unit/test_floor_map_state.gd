extends GutTest

# FloorMapState — pure-data reveal tracker for the minimap (PRD #304 slice 1).
# Tracks the set of revealed room ids for the active floor. No scene tree,
# no rendering — the renderer reads revealed_ids() and the bridge writes via
# mark_revealed(). Per-floor instance; reset on floor advance lands in a
# later slice (#308).

func test_mark_revealed_then_is_revealed_returns_true():
	var s := FloorMapState.new()
	s.mark_revealed(3)
	assert_true(s.is_revealed(3))

func test_unrevealed_room_is_not_revealed():
	var s := FloorMapState.new()
	assert_false(s.is_revealed(0))

func test_mark_revealed_is_idempotent():
	# Idempotent so a per-frame "you're in room 3" tick can call mark_revealed
	# without inflating the set or double-firing future "newly revealed"
	# diff signals.
	var s := FloorMapState.new()
	s.mark_revealed(3)
	s.mark_revealed(3)
	assert_eq(s.revealed_ids().size(), 1)

func test_revealed_ids_returns_marked_set():
	var s := FloorMapState.new()
	s.mark_revealed(0)
	s.mark_revealed(2)
	s.mark_revealed(5)
	var ids := s.revealed_ids()
	assert_eq(ids.size(), 3)
	assert_true(ids.has(0))
	assert_true(ids.has(2))
	assert_true(ids.has(5))

func test_start_room_prereveal_helper():
	# Pure helper used by RoomRevealBridge.bind() so the start room is
	# revealed before the player ever moves. Returns a fresh state with
	# exactly start_id revealed.
	var s := FloorMapState.with_start_revealed(7)
	assert_true(s.is_revealed(7))
	assert_eq(s.revealed_ids().size(), 1)
