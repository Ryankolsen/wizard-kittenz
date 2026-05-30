extends GutTest

# Slice #301 (PRD #297): the boss kind is now a deterministic per-floor
# lookup via BossRoster, not a random pool draw. These tests pin the
# floor → boss-kind mapping and the no-randomness contract at the
# DungeonGenerator seam.

func test_floor_2_boss_is_sir_pickleton():
	var d := DungeonGenerator.generate(42, 2)
	assert_eq(d.boss_room().enemy_kind, EnemyData.EnemyKind.SIR_PICKLETON)

func test_floor_10_boss_is_warden_wretched():
	var d := DungeonGenerator.generate(42, 10)
	assert_eq(d.boss_room().enemy_kind, EnemyData.EnemyKind.WARDEN_WRETCHED)

func test_floor_11_loops_back_to_vacuum():
	var floor_1 := DungeonGenerator.generate(42, 1)
	var floor_11 := DungeonGenerator.generate(42, 11)
	assert_eq(floor_11.boss_room().enemy_kind, floor_1.boss_room().enemy_kind,
		"floor 11 should loop back to floor 1's boss kind")
	assert_eq(floor_11.boss_room().enemy_kind, EnemyData.EnemyKind.ROGUE_ROOMBA,
		"floor 1 / 11 boss is the Vacuum (ROGUE_ROOMBA kind)")

func test_boss_kind_is_deterministic_on_floor_not_seed():
	# Same floor + different seeds → same boss kind. This is the regression
	# guard against re-introducing a random pool draw.
	for floor_n in [1, 3, 7, 10]:
		var seeds := [1, 42, 100, 9999]
		var first_kind: int = DungeonGenerator.generate(seeds[0], floor_n).boss_room().enemy_kind
		for s in seeds:
			var d := DungeonGenerator.generate(s, floor_n)
			assert_eq(d.boss_room().enemy_kind, first_kind,
				"floor %d seed %d: boss kind drifted (random pool reintroduced?)" % [floor_n, s])

func test_boss_room_stamps_sprite_paths_from_roster():
	# Sprite paths travel on the Room so the spawn layer can plumb them
	# into EnemyData without re-querying BossRoster.
	var d := DungeonGenerator.generate(1, 2)
	var info := BossRoster.boss_for_floor(2)
	assert_eq(d.boss_room().boss_sprite_left_path, info.sprite_left_path)
	assert_eq(d.boss_room().boss_sprite_right_path, info.sprite_right_path)

func test_dungeon_generator_has_no_boss_kinds_constant():
	# Slice #301 acceptance: BOSS_ENEMY_KINDS is removed. A cheap
	# regression so a future revert doesn't silently re-introduce the
	# random-pool path.
	var consts: Dictionary = DungeonGenerator.new().get_script().get_script_constant_map()
	assert_false(consts.has("BOSS_ENEMY_KINDS"),
		"BOSS_ENEMY_KINDS should be removed in favor of BossRoster")
