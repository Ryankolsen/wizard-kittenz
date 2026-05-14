class_name LuckRewardModifier
extends RefCounted

# Pure reward math for Luck. Two effects per the PRD:
#   gold_bonus(luck)         = flat +1 gold per luck point per kill
#   rarity_bump_chance(luck) = +2% chance per luck point to promote a drop one tier
# Negative inputs clamp to 0 — enemy/minimal stat objects may legitimately ship
# luck = 0 with a downstream malus eventually.

const GOLD_PER_LUCK: int = 1
const RARITY_BUMP_PER_LUCK: float = 0.02

static func gold_bonus(luck: int) -> int:
	if luck <= 0:
		return 0
	return luck * GOLD_PER_LUCK

static func rarity_bump_chance(luck: int) -> float:
	if luck <= 0:
		return 0.0
	return luck * RARITY_BUMP_PER_LUCK
