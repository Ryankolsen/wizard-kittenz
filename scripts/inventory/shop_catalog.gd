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

# Slice 6 of PRD #201 — flat Gold price by rarity. Drives the Gear category
# (CATEGORY_GEAR); product_id on each gear row is the ItemCatalog id, so
# PurchaseGrantHandler can look the ItemData back up on grant.
const PRICE_GEAR_COMMON := 50
const PRICE_GEAR_RARE := 250
const PRICE_GEAR_EPIC := 1000

# character_class: a CharacterData.CharacterClass int. Default -1 means "no
# active character" and omits the gear category (gear is class-gated). The
# existing-rows tests pre-Slice 6 call items() with no args and keep working.
static func items(character_class: int = -1) -> Array[ShopCatalogItem]:
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

	if character_class >= 0:
		for item_data in ItemCatalog.all_items():
			if item_data.source != ItemData.Source.SHOP:
				continue
			if not ClassEligibility.is_class_allowed(item_data, character_class):
				continue
			out.append(_gear_row(item_data))

	return out

# Looks up a catalog row by product_id; null if unknown. ShopScreen and tests
# use this to read price/category/currency without rebuilding the full list.
# Gear rows are constructed lazily from ItemCatalog so the lookup works even
# when the call site doesn't know the player's class (e.g. _refresh_row).
static func find(product_id: String) -> ShopCatalogItem:
	for item in items():
		if item.product_id == product_id:
			return item
	var item_data := ItemCatalog.find(product_id)
	if item_data != null and item_data.source == ItemData.Source.SHOP:
		return _gear_row(item_data)
	return null

static func gear_price_for_rarity(rarity: int) -> int:
	match rarity:
		ItemData.Rarity.COMMON: return PRICE_GEAR_COMMON
		ItemData.Rarity.RARE: return PRICE_GEAR_RARE
		ItemData.Rarity.EPIC: return PRICE_GEAR_EPIC
	return 0

static func _gear_row(item_data: ItemData) -> ShopCatalogItem:
	# Description is left empty for gear — ShopScreen renders per-bonus labels
	# from bonus_lines instead, so any single-string description here would be
	# dead weight (and would risk re-introducing the "magic_attack +10.0"
	# regression PRD #292 closes). Rarity + humanized bonus_lines flow from
	# ItemDisplayFormatter, the same source equipment panel rows use.
	var row := ShopCatalogItem.make(
		item_data.id,
		item_data.display_name,
		"",
		CurrencyLedger.Currency.GOLD,
		gear_price_for_rarity(item_data.rarity),
		ShopCatalogItem.CATEGORY_GEAR)
	row.rarity = item_data.rarity
	row.bonus_lines = ItemDisplayFormatter.bonus_lines(item_data)
	return row
