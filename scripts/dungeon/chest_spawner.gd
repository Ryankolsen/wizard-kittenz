class_name ChestSpawner
extends RefCounted

# Pure-data placement layer for treasure chests (PRD #217 / issue #219).
# Given a Dungeon and a seeded RandomNumberGenerator, returns a set of
# placements, each a Dictionary { room_id, position, chest }. The general-pool
# count scales with dungeon size (see general_chest_count).
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

# General-pool chest count scales with dungeon size. The dungeon expanded from
# 10-14 rooms to 100-150 rooms (commit 46505ee) but the old fixed count of 5
# stayed put, so a full crawl could surface zero chests. We now spawn one
# general chest per CHEST_PER_N_ROOMS candidate rooms (non-start, non-bar),
# floored at MIN_GENERAL_CHESTS so tiny/test dungeons still feel rewarding.
# At ~1 per 5 a 100-150 room dungeon yields ~20-30 general chests (plus the
# 3 boss-room chests below).
const CHEST_PER_N_ROOMS: int = 5
const MIN_GENERAL_CHESTS: int = 3

# Number of general-pool chests for a dungeon with `candidate_count` eligible
# rooms. Pure function so it's trivially unit-testable and the orchestrator can
# reason about expected loot without re-running plan().
static func general_chest_count(candidate_count: int) -> int:
	var scaled: int = int(round(float(candidate_count) / float(CHEST_PER_N_ROOMS)))
	return max(MIN_GENERAL_CHESTS, scaled)

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
	var target_count: int = general_chest_count(candidates.size())
	for _i in range(target_count):
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
	_append_boss_placements(placements, dungeon, rng)
	return placements

# Boss-room reward chests (PRD #311 / issue #313). Appended after the
# general pool so adding/removing this branch never desyncs the general
# RNG stream against earlier slices' tests. Three chests per boss room:
# slot 0 is the guaranteed floor-tiered BOSS_ITEM drop, slots 1 and 2 are
# RARE gem chests. The boss_chest_ id namespace is disjoint from the
# general chest_ pool so the wire layer can route remote opens without
# collision.
static func _append_boss_placements(placements: Array, dungeon: Dungeon, rng: RandomNumberGenerator) -> void:
	if dungeon.boss_id < 0:
		return
	var boss_room: Room = dungeon.get_room(dungeon.boss_id)
	if boss_room == null:
		return
	# Floor number is 1-indexed; dungeon.depth is dungeons_completed.
	var floor_number: int = dungeon.depth + 1
	var kinds := [Chest.Kind.BOSS_ITEM, Chest.Kind.RARE, Chest.Kind.RARE]
	for i in range(kinds.size()):
		var offset := Vector2(
			rng.randf_range(-POSITION_HALF_RANGE_PX, POSITION_HALF_RANGE_PX),
			rng.randf_range(-POSITION_HALF_RANGE_PX, POSITION_HALF_RANGE_PX)
		)
		placements.append({
			"chest_id": "boss_chest_%d" % i,
			"room_id": boss_room.id,
			"position": offset,
			"chest": Chest.make(kinds[i], floor_number)
		})
