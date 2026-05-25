class_name DateToday
extends RefCounted

# Single wall-clock reader for the daily-login streak engine (PRD #237 /
# issue #239). The engine stays pure by accepting a date string; this
# utility is the only place that calls Time.get_date_dict_from_system,
# so the rest of the code can be exercised with injected dates.
#
# Returns device-local today as a zero-padded ISO yyyy-mm-dd string. The
# PRD's "Time source" section accepts the device-local trade-off (player
# can rewind the device clock to farm streaks) — this is intentional.

static func iso_today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]
