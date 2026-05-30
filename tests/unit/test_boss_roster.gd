extends GutTest

# PRD #297 slice 1 (#298). BossRoster is pure data — no scene tree needed.
# Vacuum maps to ROGUE_ROOMBA (the existing in-game vacuum boss kind); the
# other nine map to the new boss-only kinds added in this slice.

func test_roster_size_is_ten():
	assert_eq(BossRoster.roster_size(), 10)

func test_floor_one_returns_vacuum():
	var info := BossRoster.boss_for_floor(1)
	assert_eq(info.kind, EnemyData.EnemyKind.ROGUE_ROOMBA)
	assert_eq(info.scaling_tier, 1)

func test_floor_ten_returns_warden():
	var info := BossRoster.boss_for_floor(10)
	assert_eq(info.kind, EnemyData.EnemyKind.WARDEN_WRETCHED)
	assert_eq(info.scaling_tier, 1)

func test_floor_eleven_loops_to_vacuum_tier_two():
	var info := BossRoster.boss_for_floor(11)
	assert_eq(info.kind, EnemyData.EnemyKind.ROGUE_ROOMBA)
	assert_eq(info.scaling_tier, 2)

func test_floor_twenty_returns_warden_tier_two():
	var info := BossRoster.boss_for_floor(20)
	assert_eq(info.kind, EnemyData.EnemyKind.WARDEN_WRETCHED)
	assert_eq(info.scaling_tier, 2)

func test_floor_twentyone_returns_vacuum_tier_three():
	var info := BossRoster.boss_for_floor(21)
	assert_eq(info.kind, EnemyData.EnemyKind.ROGUE_ROOMBA)
	assert_eq(info.scaling_tier, 3)

func test_every_floor_has_display_name():
	for n in range(1, 21):
		var info := BossRoster.boss_for_floor(n)
		assert_ne(info.display_name, "", "floor %d display_name empty" % n)

func test_sprite_paths_under_assets_sprites():
	for n in range(1, 11):
		var info := BossRoster.boss_for_floor(n)
		assert_true(info.sprite_left_path.begins_with("res://assets/sprites/"),
			"floor %d sprite_left_path %s" % [n, info.sprite_left_path])
		assert_true(info.sprite_left_path.ends_with(".png"),
			"floor %d sprite_left_path not .png: %s" % [n, info.sprite_left_path])
		assert_true(info.sprite_right_path.begins_with("res://assets/sprites/"),
			"floor %d sprite_right_path %s" % [n, info.sprite_right_path])
		assert_true(info.sprite_right_path.ends_with(".png"),
			"floor %d sprite_right_path not .png: %s" % [n, info.sprite_right_path])

func test_first_loop_kinds_are_unique():
	var seen := {}
	for n in range(1, 11):
		var info := BossRoster.boss_for_floor(n)
		seen[info.kind] = true
	assert_eq(seen.size(), 10, "floors 1..10 must produce 10 distinct kinds")
