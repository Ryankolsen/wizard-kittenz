extends GutTest

# Pure-logic tests for ClockHour's is_late_night window (PRD #453 / issue
# #472). current_hour() itself just wraps Time.get_datetime_dict_from_system
# and is intentionally not tested here -- callers exercise the injectable
# is_late_night(hour) path instead, same isolation shape as DateToday.

func test_hours_inside_the_late_night_window_are_late_night():
	assert_true(ClockHour.is_late_night(0), "midnight is in the late-night window")
	assert_true(ClockHour.is_late_night(3), "3 AM is in the late-night window")
	assert_true(ClockHour.is_late_night(4), "the last hour before the window's end is late-night")

func test_hours_outside_the_late_night_window_are_not_late_night():
	assert_false(ClockHour.is_late_night(5), "the window's end hour is exclusive")
	assert_false(ClockHour.is_late_night(12), "noon is not late-night")
	assert_false(ClockHour.is_late_night(23), "11 PM is not late-night")
