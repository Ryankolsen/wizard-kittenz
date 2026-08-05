extends GutTest

# Pure-logic tests for IdleTracker (PRD #453 / issue #472). Scene-tree-free
# by design, matching AchievementService's own testing convention -- no
# Player/SceneTree needed to exercise the accumulator.

func test_fires_exactly_once_when_threshold_crossed():
	var t := IdleTracker.new()
	assert_false(t.advance(299.0, false), "299s idle must not yet cross the 300s threshold")
	assert_true(t.advance(1.0, false), "crossing 300s idle must fire exactly on that frame")
	assert_false(t.advance(10.0, false), "further idle frames after firing must not re-fire")

func test_resets_on_input_activity():
	assert_false(IdleTracker.new().advance(240.0, false), "sanity: 240s alone must not fire")
	var t := IdleTracker.new()
	assert_false(t.advance(240.0, false), "4 minutes idle must not fire")
	assert_false(t.advance(0.0, true), "input activity must reset the accumulator, not fire")
	assert_false(t.advance(240.0, false), "4 more minutes idle after a reset (240s total) must not fire")
	assert_true(t.advance(60.0, false), "the remaining 60s should cross the 300s threshold post-reset")

func test_input_active_on_the_firing_frame_suppresses_the_fire():
	var t := IdleTracker.new()
	t.advance(300.0, false)
	# advance() re-checks input_active before accumulating on every call, so a
	# fresh tracker driven straight into an active frame never fires.
	var t2 := IdleTracker.new()
	assert_false(t2.advance(301.0, true), "an active-input frame must never report idle, regardless of delta")
