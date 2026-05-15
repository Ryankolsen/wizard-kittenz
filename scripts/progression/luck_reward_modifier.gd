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

# Maybe promote an item one rarity tier. Null item, luck<=0, EPIC-tier
# input, or a failed randf roll all return the input untouched. On a
# successful roll, picks a random item from the next-tier pool — bump
# bypasses ItemDropResolver's level gates because it's a reward, not a
# baseline drop. Caller's rng is consumed for both the gate roll and
# the next-tier pick.
static func bump_item(item: ItemData, luck: int, rng: RandomNumberGenerator) -> ItemData:
	if item == null:
		return null
	if luck <= 0:
		return item
	if item.rarity >= ItemData.Rarity.EPIC:
		return item
	if rng == null:
		rng = RandomNumberGenerator.new()
	if rng.randf() >= rarity_bump_chance(luck):
		return item
	var next_rarity: int = item.rarity + 1
	var pool := ItemCatalog.items_for_rarity(next_rarity)
	if pool.is_empty():
		return item
	return pool[rng.randi_range(0, pool.size() - 1)]
