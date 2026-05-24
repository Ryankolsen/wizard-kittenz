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

# Depth-gated rare unlock (PRD #217 / issue #220). Below RARE_UNLOCK_DEPTH
# every roll stays STANDARD (gold-only early dungeons — user story 12). At/
# above the threshold each placement independently rolls RARE with
# RARE_CHANCE_AFTER_UNLOCK probability (user story 11). The data layer for
# rare chests (Chest.RARE → gems) already exists, so credit happens for free.
const RARE_UNLOCK_DEPTH: int = 3
const RARE_CHANCE_AFTER_UNLOCK: float = 0.2

static func plan(dungeon: Dungeon, rng: RandomNumberGenerator) -> Array:
	var placements: Array = []
	if dungeon == null or rng == null:
		return placements
	var candidates: Array = []
	for r in dungeon.rooms:
		if r.id == dungeon.start_id:
			continue
		# Bar rooms host the tavern entrance — a large door footprint that a
		# chest would visibly overlap (and block). Treat the tavern as a hub,
		# not a loot room.
		if r.type == Room.TYPE_BAR:
			continue
		candidates.append(r)
	if candidates.is_empty():
		return placements
	var rare_unlocked: bool = dungeon.depth >= RARE_UNLOCK_DEPTH
	for _i in range(TARGET_COUNT):
		var idx: int = rng.randi_range(0, candidates.size() - 1)
		var room: Room = candidates[idx]
		var offset := Vector2(
			rng.randf_range(-POSITION_HALF_RANGE_PX, POSITION_HALF_RANGE_PX),
			rng.randf_range(-POSITION_HALF_RANGE_PX, POSITION_HALF_RANGE_PX)
		)
		# Always draw the kind roll so adding/removing the rare branch doesn't
		# desync the RNG stream against the position rolls. Below threshold the
		# draw is discarded and kind pins to STANDARD.
		var roll: float = rng.randf()
		var kind: int = Chest.Kind.STANDARD
		if rare_unlocked and roll < RARE_CHANCE_AFTER_UNLOCK:
			kind = Chest.Kind.RARE
		# chest_id derived purely from placement index so both co-op clients
		# converge on the same id when run against the same seed (slice 4 /
		# issue #221). The wire layer uses this to look up the local entity
		# for a remote open.
		placements.append({
			"chest_id": "chest_%d" % _i,
			"room_id": room.id,
			"position": offset,
			"chest": Chest.make(kind)
		})
	return placements
