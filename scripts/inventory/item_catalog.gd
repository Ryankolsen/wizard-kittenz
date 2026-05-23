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
	# Wizard Kitten — attack mage
	items.append(ItemData.make("apprentice_wand", "Apprentice Wand", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "magic_attack", 3.0))
	items.append(ItemData.make("arcane_staff", "Arcane Staff", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "magic_attack", 6.0))
	items.append(ItemData.make("starfire_rod", "Starfire Rod", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 10.0))
	items.append(ItemData.make("mage_robe", "Mage Robe", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "max_mp", 5.0))
	items.append(ItemData.make("sorcerer_vestments", "Sorcerer Vestments", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_mp", 15.0))
	items.append(ItemData.make("archmage_cloak", "Archmage Cloak", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "mp_regen", 0.5))
	items.append(ItemData.make("focus_crystal", "Focus Crystal", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "magic_attack", 2.0))
	items.append(ItemData.make("mana_ring", "Mana Ring", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "max_mp", 10.0))
	items.append(ItemData.make("eye_of_insight", "Eye of Insight", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "crit_chance", 0.20))
	# Sleepy Kitten — healing mage
	items.append(ItemData.make("healing_wand", "Healing Wand", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "magic_attack", 2.0))
	items.append(ItemData.make("dreamcatcher_staff", "Dreamcatcher Staff", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "mp_regen", 0.3))
	items.append(ItemData.make("lullaby_scepter", "Lullaby Scepter", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 6.0))
	items.append(ItemData.make("cozy_scarf", "Cozy Scarf", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "regeneration", 1.0))
	items.append(ItemData.make("dream_robe", "Dream Robe", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_mp", 20.0))
	items.append(ItemData.make("moonpetal_cloak", "Moonpetal Cloak", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "mp_regen", 0.5))
	items.append(ItemData.make("catnip_charm", "Catnip Charm", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "max_mp", 5.0))
	items.append(ItemData.make("soothing_bell", "Soothing Bell", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "magic_resistance", 3.0))
	items.append(ItemData.make("star_pendant", "Star Pendant", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "regeneration", 2.0))
	# Chonk Kitten — tank
	items.append(ItemData.make("heavy_club", "Heavy Club", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 3.0))
	items.append(ItemData.make("spiked_mace", "Spiked Mace", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "attack", 5.0))
	items.append(ItemData.make("earthshaker_hammer", "Earthshaker Hammer", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "max_hp", 20.0))
	items.append(ItemData.make("iron_plate", "Iron Plate", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "defense", 3.0))
	items.append(ItemData.make("tower_shield", "Tower Shield", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_hp", 25.0))
	items.append(ItemData.make("behemoth_plate", "Behemoth Plate", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "defense", 8.0))
	items.append(ItemData.make("tubby_belt", "Tubby Belt", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "max_hp", 10.0))
	items.append(ItemData.make("stone_pendant", "Stone Pendant", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "magic_resistance", 3.0))
	items.append(ItemData.make("heart_of_the_boulder", "Heart of the Boulder", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "magic_resistance", 5.0))
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
