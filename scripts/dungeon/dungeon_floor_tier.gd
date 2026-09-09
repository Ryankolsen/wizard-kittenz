class_name DungeonFloorTier
extends RefCounted

# Pure-data module that answers "what room-count band applies to floor N?"
# — the single source of truth for the floor-tier boundaries introduced by
# PRD #589. This slice (#590) covers room-count bands only; mob-density
# bands and mob-kind pools are added to TierInfo by later slices in this
# issue chain without breaking these callers.
#
# Tier boundaries (inclusive on both ends):
#   floors 1-5   -> min_rooms 25,  max_rooms 40
#   floors 6-10  -> min_rooms 60,  max_rooms 85
#   floors 11-19 -> min_rooms 100, max_rooms 150 (matches today's
#     DungeonGenerator.MIN_ROOMS/MAX_ROOMS exactly — a no-op tier)
#   floors 20+   -> min_rooms 170, max_rooms 220 (no upper bound)
#
# floor_number <= 0 clamps to floor 1's band, mirroring
# BossRoster.boss_for_floor's maxi(1, floor_number) pattern.

class TierInfo extends RefCounted:
	var min_rooms: int = 0
	var max_rooms: int = 0

static func for_floor(floor_number: int) -> TierInfo:
	var n := maxi(1, floor_number)
	var info := TierInfo.new()
	if n <= 5:
		info.min_rooms = 25
		info.max_rooms = 40
	elif n <= 10:
		info.min_rooms = 60
		info.max_rooms = 85
	elif n <= 19:
		info.min_rooms = 100
		info.max_rooms = 150
	else:
		info.min_rooms = 170
		info.max_rooms = 220
	return info
