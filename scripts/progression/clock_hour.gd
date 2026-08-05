class_name ClockHour
extends RefCounted

# Single wall-clock reader for "3 AM Kitten" late-night detection (issue
# #472). Mirrors DateToday's isolation pattern -- the only place that calls
# Time.get_datetime_dict_from_system, so is_late_night can be exercised with
# an injected hour instead of depending on the real system clock in tests.
# Device-local time, same "player can rewind the clock" trade-off DateToday
# already accepts for the daily-login streak.

const LATE_NIGHT_START_HOUR: int = 0
const LATE_NIGHT_END_HOUR: int = 5

static func current_hour() -> int:
	return int(Time.get_datetime_dict_from_system().hour)

static func is_late_night(hour: int) -> bool:
	return hour >= LATE_NIGHT_START_HOUR and hour < LATE_NIGHT_END_HOUR
