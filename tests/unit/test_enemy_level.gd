extends GutTest

# Tests for EnemyLevel — pure-function module computing a standard mob's
# level from kind + floor (PRD #376 / issue #377). Per-kind offsets and the
# floor-baseline step are tunable constants; this slice pins the floor-1
# spread and the floor-baseline climb.

func test_floor_one_pigeon_is_level_one():
	assert_eq(EnemyLevel.compute_level(EnemyData.EnemyKind.ANGRY_PIGEON, 1), 1)

func test_floor_one_per_kind_levels():
	assert_eq(EnemyLevel.compute_level(EnemyData.EnemyKind.ROGUE_ROOMBA, 1), 2)
	assert_eq(EnemyLevel.compute_level(EnemyData.EnemyKind.CATNIP_DEALER, 1), 2)
	assert_eq(EnemyLevel.compute_level(EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE, 1), 3)
	assert_eq(EnemyLevel.compute_level(EnemyData.EnemyKind.DOG_KNIGHT, 1), 4)

func test_floor_two_band_shifts_up():
	# Floor baseline climbs by +2 per floor.
	assert_eq(EnemyLevel.compute_level(EnemyData.EnemyKind.ANGRY_PIGEON, 2), 3)
	assert_eq(EnemyLevel.compute_level(EnemyData.EnemyKind.DOG_KNIGHT, 2), 6)

func test_floor_below_one_treated_as_one():
	assert_eq(
		EnemyLevel.compute_level(EnemyData.EnemyKind.ANGRY_PIGEON, 0),
		EnemyLevel.compute_level(EnemyData.EnemyKind.ANGRY_PIGEON, 1))
