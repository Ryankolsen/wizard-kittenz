class_name ItemDropResolver
extends RefCounted

# Stateless drop resolver for the Items System (PRD #73 / issue #75).
# Decides whether a kill or chest open produces an item, and which one.
#
# Slice 3 of PRD #201: resolve() now takes the killer's CharacterData so
# the pool can be filtered by ClassEligibility. If the filtered pool is
# empty at the rolled rarity, fall back to the next lower rarity (same
# shape as level _gate_down).

enum Context { ENEMY, BOSS, CHEST_STANDARD, CHEST_RARE }

const DROP_CHANCE_ENEMY: float = 0.10
const DROP_CHANCE_BOSS: float = 1.0
const DROP_CHANCE_CHEST_STANDARD: float = 0.25
const DROP_CHANCE_CHEST_RARE: float = 0.50

const WEIGHT_COMMON: float = 0.70
const WEIGHT_RARE: float = 0.25
const WEIGHT_EPIC: float = 0.05

const LEVEL_GATE_COMMON: int = 1
const LEVEL_GATE_RARE: int = 6
const LEVEL_GATE_EPIC: int = 11

static func resolve(character: CharacterData, context: int, rng: RandomNumberGenerator) -> ItemData:
	if character == null:
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
	var drop_chance := _drop_chance(context)
	if rng.randf() >= drop_chance:
		return null
	var rarity := _roll_rarity(character.level, rng)
	var pool := _class_filtered_pool(rarity, character.character_class)
	while pool.is_empty() and rarity > ItemData.Rarity.COMMON:
		rarity -= 1
		pool = _class_filtered_pool(rarity, character.character_class)
	if pool.is_empty():
		return null
	var idx := rng.randi_range(0, pool.size() - 1)
	return pool[idx]

static func _class_filtered_pool(rarity: int, character_class: int) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in ItemCatalog.items_for_rarity(rarity):
		if ClassEligibility.is_class_allowed(item, character_class):
			out.append(item)
	return out

static func _drop_chance(context: int) -> float:
	match context:
		Context.ENEMY:
			return DROP_CHANCE_ENEMY
		Context.BOSS:
			return DROP_CHANCE_BOSS
		Context.CHEST_STANDARD:
			return DROP_CHANCE_CHEST_STANDARD
		Context.CHEST_RARE:
			return DROP_CHANCE_CHEST_RARE
	return 0.0

static func _roll_rarity(player_level: int, rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var rolled: int
	if roll < WEIGHT_EPIC:
		rolled = ItemData.Rarity.EPIC
	elif roll < WEIGHT_EPIC + WEIGHT_RARE:
		rolled = ItemData.Rarity.RARE
	else:
		rolled = ItemData.Rarity.COMMON
	return _gate_down(rolled, player_level)

static func _gate_down(rarity: int, player_level: int) -> int:
	if rarity == ItemData.Rarity.EPIC and player_level < LEVEL_GATE_EPIC:
		rarity = ItemData.Rarity.RARE
	if rarity == ItemData.Rarity.RARE and player_level < LEVEL_GATE_RARE:
		rarity = ItemData.Rarity.COMMON
	return rarity
