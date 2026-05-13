class_name ShopCatalog
extends RefCounted

# Single source of truth for every row rendered in ShopScreen (PRD #53).
# items() is static + side-effect-free so callers (ShopScreen, tests, future
# analytics) can read it without instancing. Item metadata lives here, not in
# the scene; owned state is resolved at render time by ShopScreen against
# PaidUnlockInventory / CharacterData / CurrencyLedger.
#
# product_id naming overlaps with PurchaseRegistry for the three class-upgrade
# rows so the BillingManager wire-up stays one product per Play Console SKU.
# class-unlock and skill rows are Gem/Gold purchases that don't go through
# IAP — their product_ids are scoped to this catalog.

const PRODUCT_GEM_BUNDLE_STARTER := "gem_bundle_starter_099"
const PRODUCT_GEM_BUNDLE_EXPLORER := "gem_bundle_explorer_499"
const PRODUCT_GEM_BUNDLE_ADVENTURER := "gem_bundle_adventurer_999"
const PRODUCT_GEM_BUNDLE_HERO := "gem_bundle_hero_1999"

const PRODUCT_CLASS_UNLOCK_THIEF := "class_unlock_thief"
const PRODUCT_CLASS_UNLOCK_NINJA := "class_unlock_ninja"

const PRODUCT_SKILL_MAGE_FIREBALL := "skill_mage_fireball"
const PRODUCT_SKILL_THIEF_SHADOWSTEP := "skill_thief_shadowstep"
const PRODUCT_SKILL_NINJA_SMOKE_BOMB := "skill_ninja_smoke_bomb"

# Gem bundle gem grants — bonus scales with tier (PRD §Gem Bundle IAP).
const GEMS_STARTER := 100
const GEMS_EXPLORER := 600
const GEMS_ADVENTURER := 1400
const GEMS_HERO := 3000

# Price in cents — encodes the $0.99 / $4.99 / $9.99 / $19.99 PRD tiers
# directly on the bundle row. Gem bundles are the one category where price
# is real-money, not Gems; ShopScreen branches on category to render.
const PRICE_CENTS_STARTER := 99
const PRICE_CENTS_EXPLORER := 499
const PRICE_CENTS_ADVENTURER := 999
const PRICE_CENTS_HERO := 1999

static func items() -> Array[ShopCatalogItem]:
	var out: Array[ShopCatalogItem] = []

	out.append(ShopCatalogItem.make(
		PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE,
		"Archmage",
		"Upgrade Mage to Archmage — tier 2 stats and spells.",
		CurrencyLedger.Currency.GEM, 1500,
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.UPGRADE_THIEF_MASTER_THIEF,
		"Master Thief",
		"Upgrade Thief to Master Thief — tier 2 stats and crit bonus.",
		CurrencyLedger.Currency.GEM, 1500,
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.UPGRADE_NINJA_SHADOW_NINJA,
		"Shadow Ninja",
		"Upgrade Ninja to Shadow Ninja — tier 2 stats and evasion.",
		CurrencyLedger.Currency.GEM, 1500,
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE))

	out.append(ShopCatalogItem.make(
		PRODUCT_CLASS_UNLOCK_THIEF,
		"Unlock Thief",
		"Unlock the Thief class for new characters.",
		CurrencyLedger.Currency.GEM, 500,
		ShopCatalogItem.CATEGORY_CLASS_UNLOCK))
	out.append(ShopCatalogItem.make(
		PRODUCT_CLASS_UNLOCK_NINJA,
		"Unlock Ninja",
		"Unlock the Ninja class for new characters.",
		CurrencyLedger.Currency.GEM, 500,
		ShopCatalogItem.CATEGORY_CLASS_UNLOCK))

	out.append(ShopCatalogItem.make(
		PRODUCT_SKILL_MAGE_FIREBALL,
		"Fireball (Mage)",
		"Launch a fiery projectile that explodes on impact.",
		CurrencyLedger.Currency.GOLD, 250,
		ShopCatalogItem.CATEGORY_SKILL))
	out.append(ShopCatalogItem.make(
		PRODUCT_SKILL_THIEF_SHADOWSTEP,
		"Shadowstep (Thief)",
		"Short-range teleport behind the nearest enemy.",
		CurrencyLedger.Currency.GOLD, 250,
		ShopCatalogItem.CATEGORY_SKILL))
	out.append(ShopCatalogItem.make(
		PRODUCT_SKILL_NINJA_SMOKE_BOMB,
		"Smoke Bomb (Ninja)",
		"Drop a smoke cloud that briefly stuns nearby enemies.",
		CurrencyLedger.Currency.GOLD, 250,
		ShopCatalogItem.CATEGORY_SKILL))

	out.append(ShopCatalogItem.make(
		PRODUCT_GEM_BUNDLE_STARTER,
		"Starter Bundle",
		"%d Gems" % GEMS_STARTER,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_STARTER,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))
	out.append(ShopCatalogItem.make(
		PRODUCT_GEM_BUNDLE_EXPLORER,
		"Explorer Bundle",
		"%d Gems" % GEMS_EXPLORER,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_EXPLORER,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))
	out.append(ShopCatalogItem.make(
		PRODUCT_GEM_BUNDLE_ADVENTURER,
		"Adventurer Bundle",
		"%d Gems" % GEMS_ADVENTURER,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_ADVENTURER,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))
	out.append(ShopCatalogItem.make(
		PRODUCT_GEM_BUNDLE_HERO,
		"Hero Bundle",
		"%d Gems" % GEMS_HERO,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_HERO,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))

	return out
