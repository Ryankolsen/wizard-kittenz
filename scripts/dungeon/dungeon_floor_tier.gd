class_name DungeonFloorTier
extends RefCounted

# Pure-data module that answers "what room-count band applies to floor N?"
# — the single source of truth for the floor-tier boundaries introduced by
# PRD #589. This slice (#590) covers room-count bands; #592 adds mob-density
# bands. Mob-kind pools are added to TierInfo by a later slice in this issue
# chain without breaking these callers.
#
# Tier boundaries (inclusive on both ends):
#   floors 1-5   -> min_rooms 25,  max_rooms 40,  mob_min 1, mob_max 3
#   floors 6-10  -> min_rooms 60,  max_rooms 85,  mob_min 2, mob_max 4
#   floors 11-19 -> min_rooms 100, max_rooms 150, mob_min 2, mob_max 6
#     (matches today's DungeonGenerator.MIN_ROOMS/MAX_ROOMS and
#     RoomPopulationPlanner.MULTI_MIN/MULTI_MAX exactly — a no-op tier)
#   floors 20+   -> min_rooms 170, max_rooms 220, mob_min 3, mob_max 8
#     (no upper bound)
#
# floor_number <= 0 clamps to floor 1's band, mirroring
# BossRoster.boss_for_floor's maxi(1, floor_number) pattern.

class TierInfo extends RefCounted:
	var min_rooms: int = 0
	var max_rooms: int = 0
	var mob_min: int = 0
	var mob_max: int = 0

static func for_floor(floor_number: int) -> TierInfo:
	var n := maxi(1, floor_number)
	var info := TierInfo.new()
	if n <= 5:
		info.min_rooms = 25
		info.max_rooms = 40
		info.mob_min = 1
		info.mob_max = 3
	elif n <= 10:
		info.min_rooms = 60
		info.max_rooms = 85
		info.mob_min = 2
		info.mob_max = 4
	elif n <= 19:
		info.min_rooms = 100
		info.max_rooms = 150
		info.mob_min = 2
		info.mob_max = 6
	else:
		info.min_rooms = 170
		info.max_rooms = 220
		info.mob_min = 3
		info.mob_max = 8
	return info
