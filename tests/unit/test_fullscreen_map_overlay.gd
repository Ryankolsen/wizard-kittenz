extends GutTest

# FullscreenMapOverlay tests — slice 3 of PRD #304 (#307). The overlay's
# input wiring and modal close affordances are scene-level; the testable
# contract is in three pure helpers:
#   - should_pause_world(session): solo → true, active co-op → false
#   - config_for_chip(d, s, l): identity-passes refs so chip + overlay
#     can never visually drift
#   - overlay_pause_state: tracks did-we-pause-on-open so close() does
#     not stomp on an unrelated pause

const FullscreenMapOverlay := preload("res://scripts/ui/fullscreen_map_overlay.gd")

func test_pause_decision_pauses_in_solo():
	# Solo run = no CoopSession on GameState. Overlay should pause the tree
	# so the player can study the map without dying.
	assert_true(FullscreenMapOverlay.should_pause_world(null))

class _ActiveSessionStub:
	# Stand-in for a started CoopSession — saves the test from constructing
	# a Dungeon and calling session.start() just to flip _active.
	func is_active() -> bool:
		return true

func test_close_handler_unpauses_when_it_paused():
	# State-machine guard: close() should only unpause the tree if THIS
	# overlay's open() was the one that paused it. Otherwise closing the
	# map could stomp on an unrelated pause from another source (e.g. the
	# pause menu opened underneath while the overlay was up).
	var state := FullscreenMapOverlay.OverlayPauseState.new()
	# Solo open → records did-pause = true.
	state.mark_opened(true)
	assert_true(state.should_unpause_on_close())
	# After close, the flag clears so a re-open's decision is independent.
	state.mark_closed()
	assert_false(state.should_unpause_on_close())

func test_close_handler_does_not_unpause_when_open_did_not_pause():
	# Co-op open → did-pause = false → close must NOT touch the pause flag.
	var state := FullscreenMapOverlay.OverlayPauseState.new()
	state.mark_opened(false)
	assert_false(state.should_unpause_on_close())

func test_overlay_uses_same_floor_map_state_as_chip():
	# Story 20 / PRD design: the overlay's renderer must be driven by the
	# SAME instances as the chip — not copies — so a room revealed while
	# the overlay is open shows up immediately, and the two views literally
	# cannot drift in look. Identity equality, not deep equality.
	var d := Dungeon.new()
	d.add_room(Room.make(0, Room.TYPE_START))
	d.start_id = 0
	var s := FloorMapState.new()
	var l := DungeonLayout.new()
	var cfg := FullscreenMapOverlay.config_for_chip(d, s, l)
	assert_true(cfg["dungeon"] == d, "dungeon ref must be identity-equal")
	assert_true(cfg["floor_state"] == s, "floor_state ref must be identity-equal")
	assert_true(cfg["layout"] == l, "layout ref must be identity-equal")

func test_pause_decision_stays_live_in_coop():
	# Active co-op session — pausing would freeze remote players too, so
	# the overlay overlays without pausing. Story 11.
	var session := _ActiveSessionStub.new()
	assert_false(FullscreenMapOverlay.should_pause_world(session))
