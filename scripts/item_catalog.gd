class_name ItemCatalog
extends RefCounted

# Static registry of all items defined in PRD #73. Pure data — no logic,
# no scenes. Other items-system slices (ItemDropResolver, ItemInventory,
# ItemStatApplicator) read from here.

static func all_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	items.append(ItemData.make("iron_sword", "Iron Sword", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0))
	items.append(ItemData.make("silver_sword", "Silver Sword", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "attack", 5.0))
	items.append(ItemData.make("enchanted_blade", "Enchanted Blade", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 8.0))
	items.append(ItemData.make("leather_vest", "Leather Vest", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "defense", 2.0))
	items.append(ItemData.make("chain_mail", "Chain Mail", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_hp", 15.0))
	items.append(ItemData.make("dragon_scale", "Dragon Scale", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "defense", 6.0))
	items.append(ItemData.make("lucky_charm", "Lucky Charm", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "luck", 3.0))
	items.append(ItemData.make("swift_ring", "Swift Ring", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "speed", 10.0))
	items.append(ItemData.make("shadow_amulet", "Shadow Amulet", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "evasion", 0.08))
	return items

static func items_for_slot(slot: ItemData.Slot) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in all_items():
		if item.slot == slot:
			out.append(item)
	return out

static func items_for_rarity(rarity: ItemData.Rarity) -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in all_items():
		if item.rarity == rarity:
			out.append(item)
	return out

static func find(id: String) -> ItemData:
	for item in all_items():
		if item.id == id:
			return item
	return null
