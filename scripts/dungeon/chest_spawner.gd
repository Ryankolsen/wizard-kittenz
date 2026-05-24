class_name ChestSpawner
extends RefCounted

# Pure-data placement layer for treasure chests (PRD #217 / issue #219).
# Given a Dungeon and a seeded RandomNumberGenerator, returns up to
# TARGET_COUNT placements, each a Dictionary { room_id, position, chest }.
#
# Slice 2 keeps every roll STANDARD; the rare-unlock branch lands in slice 3
# (#220). Multiple chests per room are allowed — sampling is with replacement
# across the non-start rooms so a deep dungeon's distribution feels organic
# (some rooms with 2, some with 0) rather than forcibly spread.
#
# Position is randomized within a fixed half-bounds box around the room
# center. The data layer doesn't import DungeonLayout — the orchestrator
# adds room_center_world(room_id) to the returned offset at instantiation
# time. Keeping the spawner layout-agnostic preserves the "pure-data,
# easy to unit-test" property RoomSpawnPlanner established.

const TARGET_COUNT: int = 5

# Half-width / half-height of the random offset box around a room's center,
# in pixels. ROOM_SIZE_PX is 192 (DungeonLayout); ±70 keeps chests inside
# the room footprint with margin for the floor border. Boss rooms (384 px)
# also accommodate this range comfortably.
const POSITION_HALF_RANGE_PX: float = 70.0

static func plan(dungeon: Dungeon, rng: RandomNumberGenerator) -> Array:
	var placements: Array = []
	if dungeon == null or rng == null:
		return placements
	var candidates: Array = []
	for r in dungeon.rooms:
		if r.id == dungeon.start_id:
			continue
		candidates.append(r)
	if candidates.is_empty():
		return placements
	for _i in range(TARGET_COUNT):
		var idx: int = rng.randi_range(0, candidates.size() - 1)
		var room: Room = candidates[idx]
		var offset := Vector2(
			rng.randf_range(-POSITION_HALF_RANGE_PX, POSITION_HALF_RANGE_PX),
			rng.randf_range(-POSITION_HALF_RANGE_PX, POSITION_HALF_RANGE_PX)
		)
		placements.append({
			"room_id": room.id,
			"position": offset,
			"chest": Chest.make(Chest.Kind.STANDARD)
		})
	return placements
