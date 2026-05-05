class_name ProgressionSystem
extends RefCounted

# XP required to advance from `level` to `level + 1`. Linear curve:
# L1->L2 = 5, L2->L3 = 10, L3->L4 = 15. Easy to reason about for early
# pacing tests; swap for a geometric curve once we have playtest data.
static func xp_to_next_level(level: int) -> int:
	return 5 + maxi(0, level - 1) * 5

# Adds XP to the character, applying any level-ups that the new total triggers.
# Returns the number of levels gained. Negative or zero amounts are a no-op so
# kill rewards from a future debuff/penalty system can't drive xp below zero.
static func add_xp(c: CharacterData, amount: int) -> int:
	if amount <= 0:
		return 0
	c.xp += amount
	var levels_gained := 0
	while c.xp >= xp_to_next_level(c.level):
		c.xp -= xp_to_next_level(c.level)
		c.level += 1
		levels_gained += 1
		_apply_level_up(c)
	return levels_gained

# On level-up: bump max_hp via the per-class curve already on CharacterData
# and heal up by the same delta — feels rewarding without fully restoring HP.
# attack/defense don't scale with level yet (the per-class helpers ignore lvl);
# wire those in once #9/#10 give us per-class growth curves.
static func _apply_level_up(c: CharacterData) -> void:
	var new_max_hp := CharacterData.base_max_hp_for(c.character_class, c.level)
	var hp_gain := new_max_hp - c.max_hp
	c.max_hp = new_max_hp
	c.hp = mini(c.hp + hp_gain, c.max_hp)
