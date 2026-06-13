class_name RoomPopulationPlanner
extends RefCounted

# Pure mob-population module (#371). Given a seeded RNG and a Room type,
# returns the list of enemy kinds the generator should stamp on that room.
#
# Rules (per PRD #369):
#   - TYPE_STANDARD: ~50% single-mob, ~50% multi-mob. Multi rolls a count
#     uniformly in [MULTI_MIN, MULTI_MAX]. Each kind is drawn from the
#     standard enemy roster.
#   - TYPE_BOSS: exactly one kind. The actual boss kind is later overwritten
#     by DungeonGenerator from BossRoster (per-floor lookup) — the planner
#     just establishes the slot.
#   - TYPE_START / TYPE_BAR / TYPE_POWERUP: empty list (no mobs).
#
# Pure / RNG-driven: same RNG state in -> same kinds out. The generator owns
# RNG seeding so per-room population is deterministic per dungeon seed.

const MULTI_MIN := 2
const MULTI_MAX := 6

static func plan_for_room_type(rng: RandomNumberGenerator, room_type: String) -> Array:
	var kinds: Array = []
	if rng == null:
		return kinds
	match room_type:
		Room.TYPE_STANDARD:
			var count := 1
			# 50/50 single vs multi. randi() & 1 keeps the RNG sequence
			# advancement minimal and avoids float bias from randf().
			if (rng.randi() & 1) == 1:
				count = rng.randi_range(MULTI_MIN, MULTI_MAX)
			for _i in range(count):
				kinds.append(_pick_standard_kind(rng))
		Room.TYPE_BOSS:
			# Placeholder slot — DungeonGenerator overwrites this with the
			# per-floor BossRoster kind. Drawing from the standard roster
			# here keeps the planner self-contained and the count == 1
			# contract testable without coupling to BossRoster.
			kinds.append(_pick_standard_kind(rng))
		_:
			pass
	return kinds

static func _pick_standard_kind(rng: RandomNumberGenerator) -> int:
	var roster: Array = DungeonGenerator.STANDARD_ENEMY_KINDS
	return roster[rng.randi_range(0, roster.size() - 1)]
