class_name StatAllocator
extends RefCounted

# Per-point increments per PRD #52. HP/MP/Attack/etc. are int deltas,
# evasion / crit_chance are float deltas in [0.0, 1.0].
const INT_INCREMENTS := {
	"max_hp": 5,
	"max_mp": 3,
	"attack": 1,
	"magic_attack": 1,
	"defense": 1,
	"magic_resistance": 1,
	"speed": 1,
	"dexterity": 1,
	"luck": 1,
	"regeneration": 1,
	"mp_regen": 1,
}

const FLOAT_INCREMENTS := {
	"evasion": 0.01,
	"crit_chance": 0.01,
}

# Spend SP from `c.skill_points` according to `plan` ({stat_name: points}).
# Per PRD #316 / issue #317: tier table (ClassStatTiers) gates allocation,
# Off-stat costs 2 SP/pt, per-(class,stat) caps are enforced, Forbidden
# stats can't be allocated. Returns true on success and mutates `c`;
# returns false and leaves `c` fully unchanged on any rule violation.
static func allocate(c: CharacterData, plan: Dictionary) -> bool:
	if c == null:
		return false
	var total_cost := 0
	for stat in plan.keys():
		if not (INT_INCREMENTS.has(stat) or FLOAT_INCREMENTS.has(stat)):
			return false
		var pts: int = int(plan[stat])
		if pts < 0:
			return false
		if pts == 0:
			continue
		var tier := ClassStatTiers.get_tier(c.character_class, stat)
		if tier == ClassStatTiers.Tier.FORBIDDEN:
			return false
		var already: int = int(c.allocated_points.get(stat, 0))
		if already + pts > ClassStatTiers.get_cap(c.character_class, stat):
			return false
		total_cost += ClassStatTiers.get_sp_cost(c.character_class, stat) * pts
	if total_cost > c.skill_points:
		return false
	for stat in plan.keys():
		var pts: int = int(plan[stat])
		if pts == 0:
			continue
		if INT_INCREMENTS.has(stat):
			var delta: int = INT_INCREMENTS[stat] * pts
			c.set(stat, c.get(stat) + delta)
			if stat == "max_hp":
				c.hp += delta
		else:
			var fdelta: float = FLOAT_INCREMENTS[stat] * float(pts)
			c.set(stat, float(c.get(stat)) + fdelta)
		c.allocated_points[stat] = int(c.allocated_points.get(stat, 0)) + pts
	c.skill_points -= total_cost
	return true
