extends GutTest

# streak_day field on KittenSaveData (PRD #237 / issue #239). Round-trips
# through JSON like last_login_date, defaults to 0 for legacy saves.

func test_streak_day_round_trips():
	var save := KittenSaveData.new()
	save.streak_day = 7
	var d := save.to_dict()
	var reloaded := KittenSaveData.from_dict(d)
	assert_eq(reloaded.streak_day, 7)

func test_legacy_save_defaults_streak_day_to_zero():
	var reloaded := KittenSaveData.from_dict({})
	assert_eq(reloaded.streak_day, 0)
