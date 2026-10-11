extends GutTest

# Tests for ReconnectCoordinator (#638) — the pure, externally-time-driven
# retry/backoff state machine for reconnect attempts. No sockets, no Nakama,
# no scene tree; `now` is always caller-supplied so these tests never sleep.

# --- core wiring -------------------------------------------------------------

func test_start_transitions_to_retrying_and_emits_started():
	var c := ReconnectCoordinator.new()
	watch_signals(c)
	c.start(0.0)
	assert_eq(c.state(), ReconnectCoordinator.State.RETRYING, "start() enters RETRYING")
	assert_signal_emitted(c, "reconnect_started")

# --- the retry gate ----------------------------------------------------------

func test_ready_for_next_attempt_true_immediately_after_start():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	c.start(0.0)
	assert_true(c.ready_for_next_attempt(0.0), "first attempt fires immediately, no forced wait")

func test_ready_for_next_attempt_false_before_interval_elapsed():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	c.start(0.0)
	c.ready_for_next_attempt(0.0)
	assert_false(c.ready_for_next_attempt(2.0), "interval hasn't elapsed since last true")

func test_ready_for_next_attempt_true_after_interval_elapsed():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	c.start(0.0)
	c.ready_for_next_attempt(0.0)
	assert_true(c.ready_for_next_attempt(5.0), "interval has elapsed, gate opens again")

func test_note_attempt_result_success_emits_succeeded():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	watch_signals(c)
	c.start(0.0)
	c.note_attempt_result(1.0, true)
	assert_eq(c.state(), ReconnectCoordinator.State.SUCCEEDED, "success transitions to SUCCEEDED")
	assert_signal_emitted(c, "reconnect_succeeded")

func test_note_attempt_result_failure_within_window_keeps_retrying():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	watch_signals(c)
	c.start(0.0)
	c.note_attempt_result(5.0, false)
	assert_eq(c.state(), ReconnectCoordinator.State.RETRYING, "still within window, stays RETRYING")
	assert_signal_not_emitted(c, "reconnect_exhausted")

func test_note_attempt_result_failure_past_window_emits_exhausted():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	watch_signals(c)
	c.start(0.0)
	c.note_attempt_result(50.0, false)
	assert_eq(c.state(), ReconnectCoordinator.State.EXHAUSTED, "past window, transitions to EXHAUSTED")
	assert_signal_emitted(c, "reconnect_exhausted")

# --- edge cases / error paths ------------------------------------------------

func test_cancel_from_retrying_forces_exhausted():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	watch_signals(c)
	c.start(0.0)
	c.cancel()
	assert_eq(c.state(), ReconnectCoordinator.State.EXHAUSTED, "cancel forces EXHAUSTED regardless of elapsed time")
	assert_signal_emitted(c, "reconnect_exhausted")

func test_cancel_from_idle_is_noop():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	watch_signals(c)
	c.cancel()
	assert_signal_not_emitted(c, "reconnect_exhausted")
	assert_eq(c.state(), ReconnectCoordinator.State.IDLE, "cancel from IDLE is a no-op")

func test_reset_returns_to_idle_without_signal():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	c.start(0.0)
	# Watch AFTER start so the started signal from setup doesn't pollute the
	# assertion below.
	watch_signals(c)
	c.reset()
	assert_signal_not_emitted(c, "reconnect_started")
	assert_signal_not_emitted(c, "reconnect_exhausted")
	assert_eq(c.state(), ReconnectCoordinator.State.IDLE, "reset returns to IDLE")

func test_start_again_after_reset_emits_started_again():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	c.start(0.0)
	c.reset()
	watch_signals(c)
	c.start(10.0)
	assert_signal_emitted(c, "reconnect_started")

func test_duplicate_start_while_retrying_is_noop():
	var c := ReconnectCoordinator.new(5.0, 45.0)
	c.start(0.0)
	watch_signals(c)
	c.start(10.0)
	assert_signal_not_emitted(c, "reconnect_started")
	# The retry window's elapsed-time baseline must still be anchored to the
	# original start(0.0) call, not reset by the no-op duplicate start(10.0).
	# If it had reset, now=50.0 would read as elapsed=40.0 (still within the
	# 45s window); anchored to 0.0, elapsed=50.0 is past-window.
	c.note_attempt_result(50.0, false)
	assert_eq(c.state(), ReconnectCoordinator.State.EXHAUSTED, "window baseline unaffected by duplicate start")
