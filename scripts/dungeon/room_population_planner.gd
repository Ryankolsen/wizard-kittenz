class_name RoomPopulationPlanner
extends RefCounted

# Pure mob-population module (#371). Given a seeded RNG and a Room type,
# returns the list of enemy kinds the generator should stamp on that room.
#
# Rules (per PRD #369, floor-tier-gated per PRD #589 / issue #594):
#   - TYPE_STANDARD: ~50% single-mob, ~50% multi-mob. Multi rolls a count
#     uniformly in [tier.mob_min, tier.mob_max] where tier is
#     DungeonFloorTier.for_floor(floor_number). Each kind is drawn from
#     tier.kind_pool.
#   - TYPE_BOSS: exactly one kind. The actual boss kind is later overwritten
#     by DungeonGenerator from BossRoster (per-floor lookup) — the planner
#     just establishes the slot. This placeholder draw is NOT tier-gated; it
#     always draws from the full DungeonGenerator.STANDARD_ENEMY_KINDS roster
#     regardless of floor_number.
#   - TYPE_START / TYPE_BAR / TYPE_POWERUP: empty list (no mobs).
#
# Pure / RNG-driven: same RNG state in -> same kinds out. The generator owns
# RNG seeding so per-room population is deterministic per dungeon seed.

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
static func plan_for_room_type(rng: RandomNumberGenerator, room_type: String, floor_number: int = 1) -> Array:
	var kinds: Array = []
	if rng == null:
		return kinds
	match room_type:
		Room.TYPE_STANDARD:
			var roll := _roll_standard_room(rng, floor_number)
			for _i in range(roll.count):
				kinds.append(_pick_standard_kind(rng, roll.tier.kind_pool))
		Room.TYPE_BOSS:
			# Placeholder slot, not tier-gated — see the class doc comment above.
			kinds.append(_pick_standard_kind(rng, DungeonGenerator.STANDARD_ENEMY_KINDS))
		_:
			pass
	return kinds

# Shared by plan_for_room_type and plan_full_for_room_type: looks up the
# floor's tier and rolls the 50/50 single-vs-multi spawn count from it.
# randi() & 1 keeps RNG sequence advancement minimal and avoids float bias
# from randf().
static func _roll_standard_room(rng: RandomNumberGenerator, floor_number: int) -> Dictionary:
	var tier := DungeonFloorTier.for_floor(floor_number)
	var count := 1
	if (rng.randi() & 1) == 1:
		count = rng.randi_range(tier.mob_min, tier.mob_max)
	return {"tier": tier, "count": count}

static func _pick_standard_kind(rng: RandomNumberGenerator, pool: Array) -> int:
	return pool[rng.randi_range(0, pool.size() - 1)]

# Returns {kinds: Array[int], elites: Array[bool], elite_bonuses: Array[int]}
# parallel arrays of length N (one entry per spawn). Used by DungeonGenerator
# so the elite roll (PRD #380) shares the same RNG instance as the kind/count
# rolls — host and clients seeded identically agree on which spawns are elite.
#
# RNG consumption order per standard-room spawn: pick_kind → elite_roll →
# (if elite) bonus_roll. Bosses skip both elite rolls entirely so they don't
# consume RNG state and shift the next room's rolls. Non-combat rooms return
# empty arrays without consuming RNG (matches plan_for_room_type).
static func plan_full_for_room_type(rng: RandomNumberGenerator, room_type: String, floor_number: int = 1) -> Dictionary:
	var kinds: Array = []
	var elites: Array = []
	var bonuses: Array = []
	if rng == null:
		return {"kinds": kinds, "elites": elites, "elite_bonuses": bonuses}
	match room_type:
		Room.TYPE_STANDARD:
			var roll := _roll_standard_room(rng, floor_number)
			for _i in range(roll.count):
				kinds.append(_pick_standard_kind(rng, roll.tier.kind_pool))
				if rng.randf() < ELITE_CHANCE:
					elites.append(true)
					bonuses.append(rng.randi_range(ELITE_LEVEL_BONUS_MIN, ELITE_LEVEL_BONUS_MAX))
				else:
					elites.append(false)
					bonuses.append(0)
		Room.TYPE_BOSS:
			# Placeholder slot, not tier-gated — see the class doc comment above.
			kinds.append(_pick_standard_kind(rng, DungeonGenerator.STANDARD_ENEMY_KINDS))
			elites.append(false)
			bonuses.append(0)
		_:
			pass
	return {"kinds": kinds, "elites": elites, "elite_bonuses": bonuses}
