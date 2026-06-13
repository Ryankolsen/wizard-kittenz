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

# Elite roll (PRD #376 / issue #380). Each standard-mob spawn rolls
# independently against this chance from the shared RNG. Bosses are never
# elite — the boss branch in plan_full_for_room_type skips the roll entirely
# rather than rolling-then-overriding so the boss path doesn't consume RNG
# state and shift downstream room rolls.
const ELITE_CHANCE: float = 0.10
const ELITE_LEVEL_BONUS_MIN: int = 3
const ELITE_LEVEL_BONUS_MAX: int = 5

# Legacy kinds-only entry point. Kept for callers / tests that only need the
# kind list; the dungeon generator uses plan_full_for_room_type (#380) so the
# elite roll uses the same RNG without disturbing this function's contract.
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

# Returns {kinds: Array[int], elites: Array[bool], elite_bonuses: Array[int]}
# parallel arrays of length N (one entry per spawn). Used by DungeonGenerator
# so the elite roll (PRD #380) shares the same RNG instance as the kind/count
# rolls — host and clients seeded identically agree on which spawns are elite.
#
# RNG consumption order per standard-room spawn: pick_kind → elite_roll →
# (if elite) bonus_roll. Bosses skip both elite rolls entirely so they don't
# consume RNG state and shift the next room's rolls. Non-combat rooms return
# empty arrays without consuming RNG (matches plan_for_room_type).
static func plan_full_for_room_type(rng: RandomNumberGenerator, room_type: String) -> Dictionary:
	var kinds: Array = []
	var elites: Array = []
	var bonuses: Array = []
	if rng == null:
		return {"kinds": kinds, "elites": elites, "elite_bonuses": bonuses}
	match room_type:
		Room.TYPE_STANDARD:
			var count := 1
			if (rng.randi() & 1) == 1:
				count = rng.randi_range(MULTI_MIN, MULTI_MAX)
			for _i in range(count):
				kinds.append(_pick_standard_kind(rng))
				if rng.randf() < ELITE_CHANCE:
					elites.append(true)
					bonuses.append(rng.randi_range(ELITE_LEVEL_BONUS_MIN, ELITE_LEVEL_BONUS_MAX))
				else:
					elites.append(false)
					bonuses.append(0)
		Room.TYPE_BOSS:
			kinds.append(_pick_standard_kind(rng))
			elites.append(false)
			bonuses.append(0)
		_:
			pass
	return {"kinds": kinds, "elites": elites, "elite_bonuses": bonuses}
