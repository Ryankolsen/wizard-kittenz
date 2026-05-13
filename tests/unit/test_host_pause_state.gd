extends GutTest

# Tests for HostPauseState — the per-match pause flag owned by NakamaLobby
# and bridged into get_tree().paused by GameState. Pure data, edge-gated
# so duplicate OP_HOST_PAUSE packets don't re-fire host_paused.

func test_defaults_to_unpaused():
	var s := HostPauseState.new()
	assert_false(s.is_paused(), "fresh state is unpaused")

func test_set_paused_rising_edge_returns_true():
	var s := HostPauseState.new()
	assert_true(s.set_paused(true), "false -> true is a real edge")
	assert_true(s.is_paused())

func test_set_paused_duplicate_returns_false():
	# Edge-gate is what suppresses re-emission on duplicate wire packets —
	# without it, a flaky network re-delivering OP_HOST_PAUSE would re-fire
	# host_paused on every duplicate. Pinning the contract here.
	var s := HostPauseState.new()
	s.set_paused(true)
	assert_false(s.set_paused(true), "true -> true is not an edge")

func test_set_paused_falling_edge_returns_true():
	var s := HostPauseState.new()
	s.set_paused(true)
	assert_true(s.set_paused(false), "true -> false is a real edge")
	assert_false(s.is_paused())

func test_clear_drops_state():
	var s := HostPauseState.new()
	s.set_paused(true)
	s.clear()
	assert_false(s.is_paused(), "clear() resets to unpaused")
