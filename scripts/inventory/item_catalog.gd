class_name ItemCatalog
extends RefCounted

# Static registry of all items defined in PRD #73. Pure data — no logic,
# no scenes. Other items-system slices (ItemDropResolver, ItemInventory,
# ItemStatApplicator) read from here.

const _BATTLE := [CharacterData.CharacterClass.BATTLE_KITTEN]
const _WIZARD := [CharacterData.CharacterClass.WIZARD_KITTEN]
const _SLEEPY := [CharacterData.CharacterClass.SLEEPY_KITTEN]
const _CHONK := [CharacterData.CharacterClass.CHONK_KITTEN]
const _GENERIC := [
	CharacterData.CharacterClass.BATTLE_KITTEN,
	CharacterData.CharacterClass.WIZARD_KITTEN,
	CharacterData.CharacterClass.SLEEPY_KITTEN,
	CharacterData.CharacterClass.CHONK_KITTEN,
]

static func all_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	items.append(ItemData.make("iron_sword", "Slippery Mackerel", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0, _BATTLE))
	items.append(ItemData.make("silver_sword", "Alley-Cat Cutlass", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "attack", 5.0, _BATTLE))
	items.append(ItemData.make_multi("enchanted_blade", "Clawbur", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, [
		StatBonus.make("attack", 4.0),
		StatBonus.make("magic_attack", 4.0),
	], _BATTLE))
	items.append(ItemData.make("leather_vest", "Leather Vest", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "defense", 2.0, _BATTLE))
	items.append(ItemData.make("chain_mail", "Chain Mail", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_hp", 15.0, _GENERIC))
	items.append(ItemData.make("dragon_scale", "Dragon Scale", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "defense", 6.0, _BATTLE))
	items.append(ItemData.make("lucky_charm", "Lucky Charm", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "luck", 3.0, _GENERIC))
	items.append(ItemData.make("swift_ring", "Swift Ring", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "speed", 10.0, _GENERIC))
	items.append(ItemData.make("shadow_amulet", "Shadow Amulet", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "evasion", 0.08, _GENERIC))
	# Wizard Kitten — attack mage
	items.append(ItemData.make("apprentice_wand", "Birthday Sparkler", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "magic_attack", 3.0, _WIZARD))
	items.append(ItemData.make("arcane_staff", "Crackle Wand", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "magic_attack", 6.0, _WIZARD))
	items.append(ItemData.make("starfire_rod", "Comet Caller", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 10.0, _WIZARD))
	items.append(ItemData.make("mage_robe", "Mage Robe", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "max_mp", 5.0, _WIZARD))
	items.append(ItemData.make("sorcerer_vestments", "Sorcerer Vestments", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_mp", 15.0, _WIZARD))
	items.append(ItemData.make("archmage_cloak", "Archmage Cloak", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "mp_regen", 0.5, _WIZARD))
	items.append(ItemData.make("focus_crystal", "Focus Crystal", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "magic_attack", 2.0, _WIZARD))
	items.append(ItemData.make("mana_ring", "Mana Ring", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "max_mp", 10.0, _WIZARD))
	items.append(ItemData.make("eye_of_insight", "Eye of Insight", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "crit_chance", 0.20, _WIZARD))
	# Sleepy Kitten — healing mage
	items.append(ItemData.make("healing_wand", "Healing Wand", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "magic_attack", 2.0, _SLEEPY))
	items.append(ItemData.make("dreamcatcher_staff", "Dreamcatcher Staff", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "mp_regen", 0.3, _SLEEPY))
	items.append(ItemData.make("lullaby_scepter", "Lullaby Scepter", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 6.0, _SLEEPY))
	items.append(ItemData.make("cozy_scarf", "Cozy Scarf", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "regeneration", 1.0, _SLEEPY))
	items.append(ItemData.make("dream_robe", "Dream Robe", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_mp", 20.0, _SLEEPY))
	items.append(ItemData.make("moonpetal_cloak", "Moonpetal Cloak", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "mp_regen", 0.5, _SLEEPY))
	items.append(ItemData.make("catnip_charm", "Catnip Charm", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "max_mp", 5.0, _SLEEPY))
	items.append(ItemData.make("soothing_bell", "Soothing Bell", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "magic_resistance", 3.0, _SLEEPY))
	items.append(ItemData.make("star_pendant", "Star Pendant", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "regeneration", 2.0, _SLEEPY))
	# Chonk Kitten — tank
	items.append(ItemData.make("heavy_club", "Heavy Club", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 3.0, _CHONK))
	items.append(ItemData.make("spiked_mace", "Spiked Mace", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "attack", 5.0, _CHONK))
	items.append(ItemData.make("earthshaker_hammer", "Earthshaker Hammer", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "max_hp", 20.0, _CHONK))
	items.append(ItemData.make("iron_plate", "Iron Plate", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "defense", 3.0, _CHONK))
	items.append(ItemData.make("tower_shield", "Tower Shield", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_hp", 25.0, _CHONK))
	items.append(ItemData.make("behemoth_plate", "Behemoth Plate", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "defense", 8.0, _CHONK))
	items.append(ItemData.make("tubby_belt", "Tubby Belt", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "max_hp", 10.0, _CHONK))
	items.append(ItemData.make("stone_pendant", "Stone Pendant", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "magic_resistance", 3.0, _CHONK))
	items.append(ItemData.make("heart_of_the_boulder", "Heart of the Boulder", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "magic_resistance", 5.0, _CHONK))
	# --- Slice 4 expansion: +9 per class ---
	# Battle Kitten — second wave
	items.append(ItemData.make("rusted_dagger", "Pointy Stick", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0, _BATTLE))
	items.append(ItemData.make("knights_sabre", "Tin-Knight Sabre", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "attack", 5.0, _BATTLE))
	items.append(ItemData.make("dragonslayer_greatsword", "Catana", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "attack", 9.0, _BATTLE))
	items.append(ItemData.make("scout_jerkin", "Scout Jerkin", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "evasion", 0.03, _BATTLE))
	items.append(ItemData.make("knights_breastplate", "Knight's Breastplate", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "defense", 4.0, _BATTLE))
	items.append(ItemData.make("warlord_aegis", "Warlord Aegis", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "max_hp", 30.0, _BATTLE))
	items.append(ItemData.make("warriors_band", "Warrior's Band", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "attack", 1.0, _BATTLE))
	items.append(ItemData.make("berserker_pendant", "Berserker Pendant", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "crit_chance", 0.10, _BATTLE))
	items.append(ItemData.make("champions_medal", "Champion's Medal", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "attack", 5.0, _BATTLE))
	# Wizard Kitten — second wave
	items.append(ItemData.make("novice_wand", "Firefly Jar", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "magic_attack", 3.0, _WIZARD))
	items.append(ItemData.make("runed_staff", "Stormtwig Staff", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "magic_attack", 6.0, _WIZARD))
	items.append(ItemData.make("voidcaller_staff", "Wand of the Big Bang", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 11.0, _WIZARD))
	items.append(ItemData.make("acolyte_hood", "Acolyte Hood", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "max_mp", 6.0, _WIZARD))
	items.append(ItemData.make("enchanters_garb", "Enchanter's Garb", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "magic_resistance", 3.0, _WIZARD))
	items.append(ItemData.make("celestial_mantle", "Celestial Mantle", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "max_mp", 30.0, _WIZARD))
	items.append(ItemData.make("mana_pebble", "Mana Pebble", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "max_mp", 4.0, _WIZARD))
	items.append(ItemData.make("scryers_lens", "Scryer's Lens", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "magic_attack", 4.0, _WIZARD))
	items.append(ItemData.make("orb_of_eternity", "Orb of Eternity", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "mp_regen", 0.6, _WIZARD))
	# Sleepy Kitten — second wave
	items.append(ItemData.make("feather_wand", "Feather Wand", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "magic_attack", 2.0, _SLEEPY))
	items.append(ItemData.make("cloud_staff", "Cloud Staff", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "magic_attack", 4.0, _SLEEPY))
	items.append(ItemData.make("starlight_caduceus", "Starlight Caduceus", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "mp_regen", 0.5, _SLEEPY))
	items.append(ItemData.make("warm_nightgown", "Warm Nightgown", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "regeneration", 1.0, _SLEEPY))
	items.append(ItemData.make("comfy_quilt", "Comfy Quilt", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "max_hp", 15.0, _SLEEPY))
	items.append(ItemData.make("dreamweaver_shroud", "Dreamweaver Shroud", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "regeneration", 3.0, _SLEEPY))
	items.append(ItemData.make("catnap_ribbon", "Catnap Ribbon", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "mp_regen", 0.2, _SLEEPY))
	items.append(ItemData.make("silken_locket", "Silken Locket", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "regeneration", 1.5, _SLEEPY))
	items.append(ItemData.make("heart_of_the_dream", "Heart of the Dream", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "max_mp", 25.0, _SLEEPY))
	# Chonk Kitten — second wave
	items.append(ItemData.make("oak_cudgel", "Oak Cudgel", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 3.0, _CHONK))
	items.append(ItemData.make("bone_crusher", "Bone Crusher", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "attack", 6.0, _CHONK))
	items.append(ItemData.make("mountain_maul", "Mountain Maul", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "attack", 9.0, _CHONK))
	items.append(ItemData.make("padded_gambeson", "Padded Gambeson", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "max_hp", 8.0, _CHONK))
	items.append(ItemData.make("bulwark_cuirass", "Bulwark Cuirass", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "defense", 5.0, _CHONK))
	items.append(ItemData.make("titanic_aegis", "Titanic Aegis", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "max_hp", 40.0, _CHONK))
	items.append(ItemData.make("thick_collar", "Thick Collar", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "defense", 1.0, _CHONK))
	items.append(ItemData.make("granite_pendant", "Granite Pendant", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "defense", 3.0, _CHONK))
	items.append(ItemData.make("indomitable_locket", "Indomitable Locket", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "max_hp", 50.0, _CHONK))
	# --- Slice 6: SHOP-only gear (one per class per rarity, mixed slots) ---
	# These never appear in the drop pool (ItemDropResolver filters source !=
	# DROP); ShopCatalog.items(character_class) is the only surface that
	# renders them. Pricing lives on the catalog row, not the ItemData.
	items.append(ItemData.make("shop_iron_dirk", "Butter Knife", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 2.0, _BATTLE, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_squires_armor", "Squire's Armor", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "defense", 4.0, _BATTLE, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_valor_band", "Valor Band", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "attack", 5.0, _BATTLE, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_apprentice_garb", "Apprentice Garb", ItemData.Slot.ARMOR, ItemData.Rarity.COMMON, "max_mp", 5.0, _WIZARD, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_arcane_signet", "Arcane Signet", ItemData.Slot.ACCESSORY, ItemData.Rarity.RARE, "magic_attack", 4.0, _WIZARD, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_archmage_staff", "Archmage's Astrolabe", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "magic_attack", 10.0, _WIZARD, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_dreamer_charm", "Dreamer Charm", ItemData.Slot.ACCESSORY, ItemData.Rarity.COMMON, "mp_regen", 0.2, _SLEEPY, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_lullaby_wand", "Lullaby Wand", ItemData.Slot.WEAPON, ItemData.Rarity.RARE, "mp_regen", 0.3, _SLEEPY, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_starcloud_mantle", "Starcloud Mantle", ItemData.Slot.ARMOR, ItemData.Rarity.EPIC, "regeneration", 3.0, _SLEEPY, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_oak_mallet", "Oak Mallet", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 3.0, _CHONK, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_iron_brigandine", "Iron Brigandine", ItemData.Slot.ARMOR, ItemData.Rarity.RARE, "defense", 5.0, _CHONK, ItemData.Source.SHOP))
	items.append(ItemData.make("shop_boulder_pendant", "Boulder Pendant", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC, "max_hp", 50.0, _CHONK, ItemData.Source.SHOP))
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
