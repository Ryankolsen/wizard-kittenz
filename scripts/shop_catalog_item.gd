class_name ShopCatalogItem
extends RefCounted

# Typed catalog entry consumed by ShopScreen (PRD #53). One product_id per
# row; currency_type uses CurrencyLedger.Currency for soft/premium routing.
# category is a free-form string (one of CATEGORY_*) so ShopScreen can group
# rows without coupling to an enum that would have to grow per content pass.

const CATEGORY_CLASS_UPGRADE := "class_upgrade"
const CATEGORY_CLASS_UNLOCK := "class_unlock"
const CATEGORY_SKILL := "skill"
const CATEGORY_GEM_BUNDLE := "gem_bundle"

var product_id: String = ""
var display_name: String = ""
var description: String = ""
var currency_type: int = CurrencyLedger.Currency.GOLD
var price: int = 0
var category: String = ""

static func make(p_product_id: String, p_display_name: String, p_description: String,
		p_currency_type: int, p_price: int, p_category: String) -> ShopCatalogItem:
	var item := ShopCatalogItem.new()
	item.product_id = p_product_id
	item.display_name = p_display_name
	item.description = p_description
	item.currency_type = p_currency_type
	item.price = p_price
	item.category = p_category
	return item
