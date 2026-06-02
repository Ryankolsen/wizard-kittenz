class_name SkillPointRespec
extends RefCounted

# One-time skill-point respec triggered on first load post-PRD #316
# (issue #319). Detects pre-tier saves via CharacterData.schema_version,
# zeroes per-stat allocations, subtracts the corresponding stat bonuses
# back off (so base stats + item bonuses remain), and refunds the
# previously-spent SP to skill_points. Bumps schema_version so subsequent
# loads no-op. Items are not touched — equipped/bag inventories live on
# ItemInventory, not CharacterData, and are reapplied after migration by
# the load callers.

# Bumped whenever the allocation rules change in a way that requires
# refunding existing characters. 0 = pre-tier (PRD #316 / before #319).
const CURRENT_VERSION := 1

# Returns true if a respec was applied, false on no-op (already current,
# or null input). Mutates the character in-place.
static func migrate(c: CharacterData) -> bool:
	if c == null:
		return false
	if c.schema_version >= CURRENT_VERSION:
		return false
	var allocs: Dictionary = c.allocated_points.duplicate()
	var refund := 0
	for stat in allocs.keys():
		var pts: int = int(allocs[stat])
		if pts <= 0:
			continue
		# SP cost is read from the *current* tier table. A retroactive
		# refund under today's rules matches "spend nothing, re-allocate
		# from scratch under the new tiers", which is what PRD #316 asks
		# for. Forbidden stats return cost 0 here — fine, since they
		# couldn't legally have been allocated under the new rules, so
		# refunding nothing for them is correct.
		refund += ClassStatTiers.get_sp_cost(c.character_class, stat) * pts
		if StatAllocator.INT_INCREMENTS.has(stat):
			var delta: int = int(StatAllocator.INT_INCREMENTS[stat]) * pts
			c.set(stat, int(c.get(stat)) - delta)
			if stat == "max_hp":
				# allocate() raised hp alongside max_hp, but hp may have
				# changed since via combat/healing. Clamp instead of
				# blind-subtract so a low-hp save doesn't go negative.
				c.hp = clampi(c.hp, 0, c.max_hp)
		elif StatAllocator.FLOAT_INCREMENTS.has(stat):
			var fdelta: float = float(StatAllocator.FLOAT_INCREMENTS[stat]) * float(pts)
			c.set(stat, float(c.get(stat)) - fdelta)
	c.allocated_points = {}
	c.skill_points += refund
	c.schema_version = CURRENT_VERSION
	return true
