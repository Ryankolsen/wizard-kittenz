extends GutTest

# PRD #589 slice 1 (#590). DungeonFloorTier is pure data — no scene tree
# needed, same style as tests/unit/test_boss_roster.gd.

func test_floor_one_returns_tier_one_band():
	var info := DungeonFloorTier.for_floor(1)
	assert_eq(info.min_rooms, 25)
	assert_eq(info.max_rooms, 40)

func test_floor_five_is_tier_one():
	var info := DungeonFloorTier.for_floor(5)
	assert_eq(info.min_rooms, 25)
	assert_eq(info.max_rooms, 40)

func test_floor_six_is_tier_two():
	var info := DungeonFloorTier.for_floor(6)
	assert_eq(info.min_rooms, 60)
	assert_eq(info.max_rooms, 85)

func test_floor_ten_is_tier_two():
	var info := DungeonFloorTier.for_floor(10)
	assert_eq(info.min_rooms, 60)
	assert_eq(info.max_rooms, 85)

func test_floor_eleven_is_tier_three():
	var info := DungeonFloorTier.for_floor(11)
	assert_eq(info.min_rooms, 100)
	assert_eq(info.max_rooms, 150)

func test_floor_nineteen_is_tier_three():
	var info := DungeonFloorTier.for_floor(19)
	assert_eq(info.min_rooms, 100)
	assert_eq(info.max_rooms, 150)

func test_floor_twenty_is_tier_four():
	var info := DungeonFloorTier.for_floor(20)
	assert_eq(info.min_rooms, 170)
	assert_eq(info.max_rooms, 220)

func test_floor_one_hundred_is_still_tier_four():
	var info := DungeonFloorTier.for_floor(100)
	assert_eq(info.min_rooms, 170)
	assert_eq(info.max_rooms, 220)

func test_floor_zero_and_negative_clamp_to_floor_one():
	var floor_one := DungeonFloorTier.for_floor(1)
	var floor_zero := DungeonFloorTier.for_floor(0)
	var floor_negative := DungeonFloorTier.for_floor(-5)
	assert_eq(floor_zero.min_rooms, floor_one.min_rooms)
	assert_eq(floor_zero.max_rooms, floor_one.max_rooms)
	assert_eq(floor_negative.min_rooms, floor_one.min_rooms)
	assert_eq(floor_negative.max_rooms, floor_one.max_rooms)
	assert_eq(floor_zero.mob_min, floor_one.mob_min)
	assert_eq(floor_zero.mob_max, floor_one.mob_max)
	assert_eq(floor_negative.mob_min, floor_one.mob_min)
	assert_eq(floor_negative.mob_max, floor_one.mob_max)

func test_floor_one_returns_tier_one_mob_density():
	var info := DungeonFloorTier.for_floor(1)
	assert_eq(info.mob_min, 1)
	assert_eq(info.mob_max, 3)

func test_tier_two_mob_density():
	var info := DungeonFloorTier.for_floor(8)
	assert_eq(info.mob_min, 2)
	assert_eq(info.mob_max, 4)

func test_tier_three_mob_density():
	var info := DungeonFloorTier.for_floor(15)
	assert_eq(info.mob_min, 2)
	assert_eq(info.mob_max, 6)

func test_tier_four_mob_density():
	var info := DungeonFloorTier.for_floor(25)
	assert_eq(info.mob_min, 3)
	assert_eq(info.mob_max, 8)
