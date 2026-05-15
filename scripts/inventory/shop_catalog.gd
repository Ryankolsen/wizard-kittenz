class_name ShopCatalog
extends RefCounted

# Single source of truth for every row rendered in ShopScreen (PRD #53).
# items() is static + side-effect-free so callers (ShopScreen, tests, future
# analytics) can read it without instancing. Item metadata lives here, not in
# the scene; owned state is resolved at render time by ShopScreen against
# PaidUnlockInventory / CharacterData / CurrencyLedger.
#
# Product IDs all flow through PurchaseRegistry so the dispatch path
# (debit-then-handle for soft-currency rows, BillingManager.start_purchase
# for gem bundles) doesn't need a parallel id table — PurchaseRegistry's
# grant_type_for / *_id_for_* helpers route every product the catalog can
# surface.

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
		PurchaseRegistry.UPGRADE_BATTLE_KITTEN_BATTLE_CAT,
		"Battle Cat",
		"Upgrade Battle Kitten to Battle Cat — tier 2 melee stats.",
		CurrencyLedger.Currency.GEM, 1500,
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.UPGRADE_WIZARD_KITTEN_WIZARD_CAT,
		"Wizard Cat",
		"Upgrade Wizard Kitten to Wizard Cat — tier 2 spell power.",
		CurrencyLedger.Currency.GEM, 1500,
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.UPGRADE_SLEEPY_KITTEN_SLEEPY_CAT,
		"Sleepy Cat",
		"Upgrade Sleepy Kitten to Sleepy Cat — tier 2 healing and regen.",
		CurrencyLedger.Currency.GEM, 1500,
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.UPGRADE_CHONK_KITTEN_CHONK_CAT,
		"Chonk Cat",
		"Upgrade Chonk Kitten to Chonk Cat — tier 2 HP and defense.",
		CurrencyLedger.Currency.GEM, 1500,
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE))

	out.append(ShopCatalogItem.make(
		PurchaseRegistry.CLASS_UNLOCK_CHONK_KITTEN,
		"Unlock Chonk Kitten",
		"Unlock the Chonk Kitten class for new characters.",
		CurrencyLedger.Currency.GEM, 500,
		ShopCatalogItem.CATEGORY_CLASS_UNLOCK))

	out.append(ShopCatalogItem.make(
		PurchaseRegistry.SKILL_UNLOCK_FIREBALL,
		"Fireball (Mage)",
		"Launch a fiery projectile that explodes on impact.",
		CurrencyLedger.Currency.GOLD, 250,
		ShopCatalogItem.CATEGORY_SKILL))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.SKILL_UNLOCK_SHADOWSTEP,
		"Shadowstep (Thief)",
		"Short-range teleport behind the nearest enemy.",
		CurrencyLedger.Currency.GOLD, 250,
		ShopCatalogItem.CATEGORY_SKILL))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.SKILL_UNLOCK_SMOKE_BOMB,
		"Smoke Bomb (Ninja)",
		"Drop a smoke cloud that briefly stuns nearby enemies.",
		CurrencyLedger.Currency.GOLD, 250,
		ShopCatalogItem.CATEGORY_SKILL))

	out.append(ShopCatalogItem.make(
		PurchaseRegistry.GEM_BUNDLE_STARTER,
		"Starter Bundle",
		"%d Gems" % GEMS_STARTER,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_STARTER,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.GEM_BUNDLE_EXPLORER,
		"Explorer Bundle",
		"%d Gems" % GEMS_EXPLORER,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_EXPLORER,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.GEM_BUNDLE_ADVENTURER,
		"Adventurer Bundle",
		"%d Gems" % GEMS_ADVENTURER,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_ADVENTURER,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))
	out.append(ShopCatalogItem.make(
		PurchaseRegistry.GEM_BUNDLE_HERO,
		"Hero Bundle",
		"%d Gems" % GEMS_HERO,
		CurrencyLedger.Currency.GEM, PRICE_CENTS_HERO,
		ShopCatalogItem.CATEGORY_GEM_BUNDLE))

	return out

# Looks up a catalog row by product_id; null if unknown. ShopScreen and tests
# use this to read price/category/currency without rebuilding the full list.
static func find(product_id: String) -> ShopCatalogItem:
	for item in items():
		if item.product_id == product_id:
			return item
	return null
