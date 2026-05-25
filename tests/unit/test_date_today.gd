extends GutTest

# DateToday is the single wall-clock reader (PRD #237 / issue #239). Assert
# format/shape rather than a specific date so the test isn't time-bound.

func test_today_iso_is_well_formed():
	var s := DateToday.iso_today()
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}$")
	assert_not_null(re.search(s), "expected yyyy-mm-dd, got: %s" % s)
	# Parses to a valid date dict via the inverse Time API.
	var parts := s.split("-")
	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])
	assert_true(year >= 1970, "year sane")
	assert_true(month >= 1 and month <= 12, "month in range")
	assert_true(day >= 1 and day <= 31, "day in range")
