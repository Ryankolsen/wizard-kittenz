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
const GRANT_GEM_BUNDLE := "gem_bundle"
const GRANT_SKILL_UNLOCK := "skill_unlock"

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
const CLASS_UNLOCK_THIEF := "class_unlock_thief"
const CLASS_UNLOCK_NINJA := "class_unlock_ninja"

# Tier 4 — Gem bundle consumable IAPs (PRD #53). Real-money product IDs; the
# grant handler routes each to a CurrencyLedger.credit(Currency.GEM, amount)
# call. Amounts intentionally match ShopCatalog.GEMS_* so the catalog row and
# the IAP grant agree on what the player paid for.
const GEM_BUNDLE_STARTER := "gem_bundle_starter"
const GEM_BUNDLE_EXPLORER := "gem_bundle_explorer"
const GEM_BUNDLE_ADVENTURER := "gem_bundle_adventurer"
const GEM_BUNDLE_HERO := "gem_bundle_hero"

# Tier 5 — skill unlock products. Soft-currency or IAP purchase routes through
# the same dispatch; skill_id_for_unlock maps the product_id to the canonical
# skill id consulted by SkillInventory. The id strings match the skill tree's
# node ids (e.g. SkillTree.make_mage_tree's "fireball").
const SKILL_UNLOCK_FIREBALL := "skill_unlock_fireball"
const SKILL_UNLOCK_SHADOWSTEP := "skill_unlock_shadowstep"
const SKILL_UNLOCK_SMOKE_BOMB := "skill_unlock_smoke_bomb"

const _GEM_BUNDLE_AMOUNTS: Dictionary = {
	GEM_BUNDLE_STARTER: 100,
	GEM_BUNDLE_EXPLORER: 600,
	GEM_BUNDLE_ADVENTURER: 1400,
	GEM_BUNDLE_HERO: 3000,
}

const _SKILL_UNLOCK_TO_SKILL_ID: Dictionary = {
	SKILL_UNLOCK_FIREBALL: "fireball",
	SKILL_UNLOCK_SHADOWSTEP: "shadowstep",
	SKILL_UNLOCK_SMOKE_BOMB: "smoke_bomb",
}

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
	CLASS_UNLOCK_THIEF,
	CLASS_UNLOCK_NINJA,
]

# product_id -> class id string consulted by UnlockRegistry.is_unlocked. The
# class id matches the lowercase string the unlock condition list keys on
# (see UnlockRegistry.DEFAULT_CONDITIONS / CharacterFactory.name_from_class).
const _CLASS_UNLOCK_TO_CLASS_ID: Dictionary = {
	CLASS_UNLOCK_ARCHMAGE: "archmage",
	CLASS_UNLOCK_THIEF: "thief",
	CLASS_UNLOCK_NINJA: "ninja",
}

const ALL_PRODUCT_IDS: Array = [
	UPGRADE_MAGE_ARCHMAGE,
	UPGRADE_THIEF_MASTER_THIEF,
	UPGRADE_NINJA_SHADOW_NINJA,
	COSMETIC_COAT_PACK,
	COSMETIC_SPELL_EFFECTS,
	COSMETIC_DUNGEON_SKINS,
	CLASS_UNLOCK_ARCHMAGE,
	CLASS_UNLOCK_THIEF,
	CLASS_UNLOCK_NINJA,
	GEM_BUNDLE_STARTER,
	GEM_BUNDLE_EXPLORER,
	GEM_BUNDLE_ADVENTURER,
	GEM_BUNDLE_HERO,
	SKILL_UNLOCK_FIREBALL,
	SKILL_UNLOCK_SHADOWSTEP,
	SKILL_UNLOCK_SMOKE_BOMB,
]

static func grant_type_for(product_id: String) -> String:
	if _CLASS_UPGRADE_TO_SOURCE.has(product_id):
		return GRANT_CLASS_UPGRADE
	if _COSMETIC_IDS.has(product_id):
		return GRANT_COSMETIC_PACK
	if _CLASS_UNLOCK_IDS.has(product_id):
		return GRANT_CLASS_UNLOCK
	if _GEM_BUNDLE_AMOUNTS.has(product_id):
		return GRANT_GEM_BUNDLE
	if _SKILL_UNLOCK_TO_SKILL_ID.has(product_id):
		return GRANT_SKILL_UNLOCK
	return ""

# Returns the Gem grant amount for a gem-bundle product id; 0 for any other
# product kind. PurchaseGrantHandler reads this on the dispatch path; the
# zero sentinel keeps a future "non-bundle product accidentally routed here"
# from minting Gems.
static func gem_amount_for(product_id: String) -> int:
	return int(_GEM_BUNDLE_AMOUNTS.get(product_id, 0))

# Returns the canonical skill_id for a skill-unlock product. Empty string for
# any other product kind so callers can branch off the empty sentinel.
static func skill_id_for_unlock(product_id: String) -> String:
	return String(_SKILL_UNLOCK_TO_SKILL_ID.get(product_id, ""))

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
