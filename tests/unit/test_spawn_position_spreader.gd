extends GutTest

# Tests for SpawnPositionSpreader (#372) — pure module that returns N distinct,
# in-bounds, non-overlapping spawn positions for a room's mob list.

const _ORIGIN := Vector2(100.0, 200.0)
const _SIZE := Vector2(192.0, 192.0)  # standard room size

# --- core wiring -----------------------------------------------------------

func test_spread_count_four_returns_four_positions():
	var positions := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, 4)
	assert_eq(positions.size(), 4, "count=4 returns 4 positions")
	for p in positions:
		assert_typeof(p, TYPE_VECTOR2, "each position is a Vector2")

# --- in-bounds + non-overlap ----------------------------------------------

func test_spread_positions_are_inside_room_rect():
	var rect := Rect2(_ORIGIN, _SIZE)
	for count in range(1, 7):
		var positions := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, count)
		for p in positions:
			assert_true(rect.has_point(p),
				"count=%d pos %s lies in rect %s" % [count, str(p), str(rect)])

func test_spread_positions_respect_min_separation():
	var min_sep: float = SpawnPositionSpreader.MIN_SEPARATION_PX
	for count in range(2, 7):
		var positions := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, count)
		for i in range(positions.size()):
			for j in range(i + 1, positions.size()):
				var d: float = (positions[i] as Vector2).distance_to(positions[j])
				assert_gte(d, min_sep,
					"count=%d positions[%d] and [%d] separated >= %f (got %f)" % [count, i, j, min_sep, d])

func test_spread_count_one_returns_room_center():
	var positions := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, 1)
	assert_eq(positions.size(), 1)
	assert_eq(positions[0], _ORIGIN + _SIZE * 0.5,
		"count=1 places the single mob at the room center (preserves single-mob behavior)")

# --- edge cases ------------------------------------------------------------

func test_spread_count_zero_returns_empty():
	var positions := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, 0)
	assert_eq(positions.size(), 0)

func test_spread_negative_count_returns_empty():
	var positions := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, -3)
	assert_eq(positions.size(), 0, "negative count is a safe no-op")

func test_spread_same_inputs_same_outputs():
	# Deterministic: same (origin, size, count) -> identical positions across
	# calls. The co-op handshake relies on every client deriving the same
	# spawn coordinates from the synced dungeon seed.
	var a := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, 5)
	var b := SpawnPositionSpreader.spread(_ORIGIN, _SIZE, 5)
	assert_eq(a.size(), b.size())
	for i in range(a.size()):
		assert_eq(a[i], b[i], "position %d matches across deterministic calls" % i)

func test_spread_different_origins_yield_different_positions():
	# Sanity: a different room origin must not produce the same world-space
	# positions — otherwise every room would spawn its mobs on top of room 0.
	var a := SpawnPositionSpreader.spread(Vector2.ZERO, _SIZE, 4)
	var b := SpawnPositionSpreader.spread(Vector2(500.0, 500.0), _SIZE, 4)
	var any_diff := false
	for i in range(a.size()):
		if a[i] != b[i]:
			any_diff = true
			break
	assert_true(any_diff, "different origins produce different positions")

func test_spread_boss_room_size_still_in_bounds():
	# Boss room is 384x384 — make sure the spreader handles the bigger rect.
	var boss_size := Vector2(384.0, 384.0)
	var rect := Rect2(_ORIGIN, boss_size)
	for count in range(1, 7):
		for p in SpawnPositionSpreader.spread(_ORIGIN, boss_size, count):
			assert_true(rect.has_point(p),
				"boss-size count=%d pos %s lies in rect" % [count, str(p)])
