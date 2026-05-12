class_name PurchaseRegistry
extends RefCounted

# Single source of truth for IAP product IDs and what each one grants. Stateless
# — `BillingManager` (#31) queries `ALL_PRODUCT_IDS` at startup, and the grant
# handler (#32) dispatches off `grant_type_for(...)`. Keeping the catalog in one
# place means a new product is a one-spot addition (the constant, the type map,
# and `ALL_PRODUCT_IDS`) — no string literals scattered through call sites.
#
# Grant types intentionally use plain strings rather than an enum so the same
# value can flow through saves, signals, and Play Console product metadata
# without coupling.

const GRANT_CLASS_UPGRADE := "class_upgrade"
const GRANT_COSMETIC_PACK := "cosmetic_pack"
const GRANT_CLASS_UNLOCK := "class_unlock"

# Tier 1 — class tier upgrades. The source class is the one being upgraded;
# `ClassTierUpgrade.TIER_MAP` owns the upgrade target. Today only Mage ->
# Archmage is wired in TIER_MAP; the other two product IDs exist so the
# Play Console catalog can be stood up ahead of the in-engine upgrades.
const UPGRADE_MAGE_ARCHMAGE := "upgrade_mage_archmage"
const UPGRADE_THIEF_MASTER_THIEF := "upgrade_thief_master_thief"
const UPGRADE_NINJA_SHADOW_NINJA := "upgrade_ninja_shadow_ninja"

# Tier 2 — cosmetic packs. Owning ids tracked in CosmeticInventory (#29).
const COSMETIC_COAT_PACK := "cosmetic_coat_pack"
const COSMETIC_SPELL_EFFECTS := "cosmetic_spell_effects"
const COSMETIC_DUNGEON_SKINS := "cosmetic_dungeon_skins"

# Tier 3 — class unlock shortcuts. PRD calls out "first unlockable class beyond
# the base three"; Archmage is the only non-base class in CharacterData today,
# so it doubles as the placeholder. Earnable via the existing UnlockRegistry
# gate (`max_level_per_class.mage >= 5`).
const CLASS_UNLOCK_ARCHMAGE := "class_unlock_archmage"

const _CLASS_UPGRADE_TO_SOURCE: Dictionary = {
	UPGRADE_MAGE_ARCHMAGE: CharacterData.CharacterClass.MAGE,
	UPGRADE_THIEF_MASTER_THIEF: CharacterData.CharacterClass.THIEF,
	UPGRADE_NINJA_SHADOW_NINJA: CharacterData.CharacterClass.NINJA,
}

const _COSMETIC_IDS: Array = [
	COSMETIC_COAT_PACK,
	COSMETIC_SPELL_EFFECTS,
	COSMETIC_DUNGEON_SKINS,
]

const _CLASS_UNLOCK_IDS: Array = [
	CLASS_UNLOCK_ARCHMAGE,
]

# product_id -> class id string consulted by UnlockRegistry.is_unlocked. The
# class id matches the lowercase string the unlock condition list keys on
# (see UnlockRegistry.DEFAULT_CONDITIONS / CharacterFactory.name_from_class).
const _CLASS_UNLOCK_TO_CLASS_ID: Dictionary = {
	CLASS_UNLOCK_ARCHMAGE: "archmage",
}

const ALL_PRODUCT_IDS: Array = [
	UPGRADE_MAGE_ARCHMAGE,
	UPGRADE_THIEF_MASTER_THIEF,
	UPGRADE_NINJA_SHADOW_NINJA,
	COSMETIC_COAT_PACK,
	COSMETIC_SPELL_EFFECTS,
	COSMETIC_DUNGEON_SKINS,
	CLASS_UNLOCK_ARCHMAGE,
]

static func grant_type_for(product_id: String) -> String:
	if _CLASS_UPGRADE_TO_SOURCE.has(product_id):
		return GRANT_CLASS_UPGRADE
	if _COSMETIC_IDS.has(product_id):
		return GRANT_COSMETIC_PACK
	if _CLASS_UNLOCK_IDS.has(product_id):
		return GRANT_CLASS_UNLOCK
	return ""

# Returns the source CharacterClass for class-upgrade products (the class being
# upgraded — the target tier lives in ClassTierUpgrade.TIER_MAP). All other
# product kinds return -1 so callers can branch off that sentinel.
static func class_for_product(product_id: String) -> int:
	if _CLASS_UPGRADE_TO_SOURCE.has(product_id):
		return int(_CLASS_UPGRADE_TO_SOURCE[product_id])
	return -1

# Returns the class id string for class-unlock products. Empty string for any
# other product kind so callers can branch off the empty sentinel without
# special-casing the lookup. The class id matches the lowercase keys
# UnlockRegistry's condition list uses (e.g. "archmage").
static func class_id_for_unlock(product_id: String) -> String:
	return String(_CLASS_UNLOCK_TO_CLASS_ID.get(product_id, ""))
