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
}

const FLOAT_INCREMENTS := {
	"evasion": 0.01,
	"crit_chance": 0.01,
}

# Spend `plan` ({stat_name: points}) points from `c.skill_points`. Returns
# true on success and mutates `c`; returns false and leaves `c` unchanged
# when the plan total exceeds available points or contains an unknown stat.
static func allocate(c: CharacterData, plan: Dictionary) -> bool:
	if c == null:
		return false
	var total := 0
	for stat in plan.keys():
		if not (INT_INCREMENTS.has(stat) or FLOAT_INCREMENTS.has(stat)):
			return false
		var pts: int = int(plan[stat])
		if pts < 0:
			return false
		total += pts
	if total > c.skill_points:
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
	c.skill_points -= total
	return true
