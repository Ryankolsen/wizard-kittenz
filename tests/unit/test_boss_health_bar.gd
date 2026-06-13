extends GutTest

# Pure-function tests for BossHealthBar.format_boss_hp — the boss bar's
# "Name  cur/max" label render. View glue (top-center placement, boss
# discovery, show/hide on spawn/death, fill width) is verified in the
# manual QA slice #249, mirroring the test split in test_enemy_health_bar.gd.

func test_format_full_hp():
	assert_eq(BossHealthBar.format_boss_hp("The Vacuum", 64, 64), "The Vacuum  64/64")

func test_format_mid_fight_value():
	assert_eq(BossHealthBar.format_boss_hp("The Vacuum", 30, 64), "The Vacuum  30/64")

func test_format_zero_hp():
	# Dead/zero HP still formats cleanly — the bar may render one extra frame
	# before the boss enemy queue_frees and the HUD's poll hides the bar.
	assert_eq(BossHealthBar.format_boss_hp("The Vacuum", 0, 64), "The Vacuum  0/64")

func test_format_empty_name_does_not_crash():
	# Defensive: an unconfigured EnemyData with a blank enemy_name renders the
	# numbers prefixed by the double-space separator instead of crashing.
	assert_eq(BossHealthBar.format_boss_hp("", 10, 10), "  10/10")

func test_ratio_zero_hp_renders_empty():
	# Pin the shared fill math the boss bar relies on — same HUD.hp_bar_ratio
	# used by the player HUD and EnemyHealthBar.
	assert_almost_eq(HUD.hp_bar_ratio(0, 64), 0.0, 0.0001)

func test_ratio_full_hp_renders_full():
	assert_almost_eq(HUD.hp_bar_ratio(64, 64), 1.0, 0.0001)

func test_should_show_when_player_inside_boss_room():
	# Player standing inside the boss room's world-space bounds -> bar shows.
	var bounds := Rect2(Vector2(100, 100), Vector2(384, 384))
	assert_true(BossHealthBar.should_show(bounds, Vector2(200, 200)))

func test_should_hide_when_player_outside_boss_room():
	# Player elsewhere in the dungeon -> bar stays hidden even though the boss
	# already exists in the tree from spawn.
	var bounds := Rect2(Vector2(100, 100), Vector2(384, 384))
	assert_false(BossHealthBar.should_show(bounds, Vector2(0, 0)))

func test_should_hide_when_bounds_have_no_area():
	# Unconfigured / arealess bounds (legacy or test boss with no room_bounds)
	# can't locate the room, so the bar stays hidden rather than showing early.
	assert_false(BossHealthBar.should_show(Rect2(), Vector2(50, 50)))

# PRD #297 / slice #302 — the bar's label render reads boss_name from
# EnemyData.enemy_name. Slice 4 wired RoomSpawnPlanner to copy the
# BossRoster display name onto EnemyData.enemy_name, so feeding the
# bar the roster name for a given floor produces a label that contains
# that floor's boss name.
func test_format_uses_roster_name_for_floor_3():
	var info := BossRoster.boss_for_floor(3)
	var label := BossHealthBar.format_boss_hp(info.display_name, 50, 50)
	assert_true(label.find("Old Lady Pearl") != -1, "label '%s' should contain Floor 3 boss name" % label)

func test_format_uses_roster_name_for_floor_2():
	var info := BossRoster.boss_for_floor(2)
	var label := BossHealthBar.format_boss_hp(info.display_name, 40, 40)
	assert_true(label.find("Sir Pickleton") != -1, "label '%s' should contain Floor 2 boss name" % label)

# PRD #376 / issue #382 — boss bar surfaces the boss's level so mob + boss
# readouts stay consistent. Level arg defaults to 0 (no label) for backward
# compat with single-floor callers that don't yet thread the level through.
func test_format_includes_level():
	assert_eq(BossHealthBar.format_boss_hp("The Vacuum", 48, 48, 3), "The Vacuum  Lv 3  48/48")

func test_format_zero_level_omits_label():
	# Empty / zero level renders the original "Name  cur/max" form without a
	# stray "Lv 0" — guards EnemyData defaults and pre-#382 callers.
	assert_eq(BossHealthBar.format_boss_hp("The Vacuum", 48, 48, 0), "The Vacuum  48/48")
