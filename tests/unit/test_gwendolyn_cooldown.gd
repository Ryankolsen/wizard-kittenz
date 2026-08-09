extends GutTest

# GwendolynCooldown (PRD #474 / issue #477). Pure resolver comparing a
# persisted last-used unix timestamp against "now" at hour granularity,
# structured like DailyStreakEngine.resolve(save, today) but per-character
# and rolling-hour rather than calendar-day. Gates Quickbar.fire_slot for
# summon_gwendolyn specifically (see test_quickbar.gd).

const _HOUR := 3600

func test_unset_last_used_is_ready():
	assert_true(GwendolynCooldown.is_ready(0, 1000))

func test_null_last_used_is_ready():
	assert_true(GwendolynCooldown.is_ready(null, 1000))

func test_thirty_minutes_elapsed_is_not_ready_with_remaining_time():
	var now := 100000
	var last_used := now - 1800
	assert_false(GwendolynCooldown.is_ready(last_used, now))
	var remaining := GwendolynCooldown.time_remaining(last_used, now)
	assert_almost_eq(remaining, 1800, 1)

func test_sixty_one_minutes_elapsed_is_ready():
	var now := 100000
	var last_used := now - (61 * 60)
	assert_true(GwendolynCooldown.is_ready(last_used, now))
	assert_eq(GwendolynCooldown.time_remaining(last_used, now), 0)

func test_exact_one_hour_boundary_is_ready_inclusive():
	# Documented choice: elapsed >= COOLDOWN_SECONDS counts as ready, so a
	# cast exactly 3600 seconds ago is not blocked.
	var now := 100000
	var last_used := now - _HOUR
	assert_true(GwendolynCooldown.is_ready(last_used, now))

func test_one_second_before_boundary_is_not_ready():
	var now := 100000
	var last_used := now - (_HOUR - 1)
	assert_false(GwendolynCooldown.is_ready(last_used, now))

func test_negative_last_used_is_safe_and_ready():
	assert_true(GwendolynCooldown.is_ready(-5, 1000))
	assert_eq(GwendolynCooldown.time_remaining(-5, 1000), 0)

func test_two_characters_resolve_independently():
	var now := 100000
	var recent := now - 600
	var old := now - (2 * _HOUR)
	assert_false(GwendolynCooldown.is_ready(recent, now))
	assert_true(GwendolynCooldown.is_ready(old, now))

func test_restart_persistence_round_trip_preserves_remaining_cooldown():
	var slot := CharacterSlotData.new()
	var now := 100000
	slot.gwendolyn_last_summon_unix = now - 1800
	var dict := slot.to_dict()
	var reloaded := CharacterSlotData.from_dict(dict)
	assert_eq(reloaded.gwendolyn_last_summon_unix, now - 1800)
	assert_false(GwendolynCooldown.is_ready(reloaded.gwendolyn_last_summon_unix, now))
	assert_almost_eq(GwendolynCooldown.time_remaining(reloaded.gwendolyn_last_summon_unix, now), 1800, 1)

func test_legacy_slot_without_field_defaults_to_ready():
	var reloaded := CharacterSlotData.from_dict({})
	assert_eq(reloaded.gwendolyn_last_summon_unix, 0)
	assert_true(GwendolynCooldown.is_ready(reloaded.gwendolyn_last_summon_unix, 100000))
