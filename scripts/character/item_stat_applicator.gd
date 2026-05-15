class_name ItemStatApplicator
extends RefCounted

# Stateless helper that applies equipped-item bonuses onto CharacterData
# fields by name. Pure data layer for the Items System (PRD #73). Callers
# (equip/unequip flows, save/load) use recompute() to reset stats to base
# then re-apply, avoiding drift from repeated additions.

const _SLOTS: Array[int] = [
	ItemData.Slot.WEAPON,
	ItemData.Slot.ARMOR,
	ItemData.Slot.ACCESSORY,
]

static func apply(inventory: ItemInventory, character: CharacterData) -> void:
	if inventory == null or character == null:
		return
	for slot in _SLOTS:
		var item: ItemData = inventory.equipped_in(slot)
		if item == null or item.stat_name == "":
			continue
		var current: Variant = character.get(item.stat_name)
		if current == null:
			continue
		character.set(item.stat_name, current + item.stat_bonus)

static func recompute(inventory: ItemInventory, character: CharacterData, base: CharacterData) -> void:
	if character == null or base == null:
		return
	_copy_stats(base, character)
	apply(inventory, character)

static func _copy_stats(src: CharacterData, dst: CharacterData) -> void:
	dst.max_hp = src.max_hp
	dst.attack = src.attack
	dst.defense = src.defense
	dst.speed = src.speed
	dst.magic_attack = src.magic_attack
	dst.max_mp = src.max_mp
	dst.magic_resistance = src.magic_resistance
	dst.dexterity = src.dexterity
	dst.evasion = src.evasion
	dst.crit_chance = src.crit_chance
	dst.luck = src.luck
	dst.regeneration = src.regeneration
