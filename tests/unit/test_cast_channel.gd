extends GutTest

# CastChannel (issue #476). Pure state module driving the Summon Gwendolyn
# cast lock/interrupt/retry contract: start/tick/on_damage_taken/is_complete.

func test_full_duration_tick_completes_channel():
	var c := CastChannel.new()
	c.start(15.0)
	c.tick(15.0)
	assert_true(c.is_complete())

func test_partial_tick_does_not_complete():
	var c := CastChannel.new()
	c.start(15.0)
	c.tick(10.0)
	assert_false(c.is_complete())
	assert_true(c.is_active())

func test_zero_cast_time_completes_immediately():
	var c := CastChannel.new()
	c.start(0.0)
	assert_true(c.is_complete())
	assert_false(c.is_active())

func test_damage_mid_channel_cancels_it():
	var c := CastChannel.new()
	c.start(15.0)
	c.tick(5.0)
	c.on_damage_taken()
	assert_true(c.is_cancelled())
	assert_false(c.is_active())
	# Cancelled channel never reports complete no matter how much more time passes.
	c.tick(100.0)
	assert_false(c.is_complete())

func test_cancelled_channel_can_restart_immediately():
	var c := CastChannel.new()
	c.start(15.0)
	c.tick(5.0)
	c.on_damage_taken()
	c.start(15.0)
	assert_true(c.is_active())
	c.tick(15.0)
	assert_true(c.is_complete())

func test_on_damage_taken_with_no_active_channel_is_safe_noop():
	var c := CastChannel.new()
	c.on_damage_taken()
	assert_false(c.is_cancelled())
	assert_false(c.is_active())
	assert_false(c.is_complete())

# progress()/remaining() back the cast-progress-bar UI above the player.

func test_progress_is_zero_before_any_tick():
	var c := CastChannel.new()
	c.start(15.0)
	assert_eq(c.progress(), 0.0)
	assert_eq(c.remaining(), 15.0)

func test_progress_and_remaining_partway_through():
	var c := CastChannel.new()
	c.start(15.0)
	c.tick(5.0)
	assert_almost_eq(c.progress(), 1.0 / 3.0, 0.0001)
	assert_almost_eq(c.remaining(), 10.0, 0.0001)

func test_progress_is_one_and_remaining_zero_on_completion():
	var c := CastChannel.new()
	c.start(15.0)
	c.tick(15.0)
	assert_eq(c.progress(), 1.0)
	assert_eq(c.remaining(), 0.0)

func test_progress_and_remaining_zero_when_idle():
	var c := CastChannel.new()
	assert_eq(c.progress(), 0.0)
	assert_eq(c.remaining(), 0.0)

func test_remaining_is_zero_after_cancellation():
	var c := CastChannel.new()
	c.start(15.0)
	c.tick(5.0)
	c.on_damage_taken()
	assert_eq(c.remaining(), 0.0)
