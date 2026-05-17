class_name ShopScreen
extends Control

# Renders ShopCatalog rows and routes Buy presses through the right grant
# pathway (PRD #53 / issue #71). Two dispatch shapes:
#
#   Soft-currency (Gold/Gem) rows  →  CurrencyLedger.debit, then
#       PurchaseGrantHandler.handle. Insufficient funds → debit returns
#       false → row is untouched, no error label (the disabled-button
#       affordance is the only feedback the PRD asks for).
#   Gem bundle rows                →  BillingManager.start_purchase. The
#       grant lands when BillingManager fires purchase_succeeded; this
#       screen also routes that signal through PurchaseGrantHandler so the
#       UI can refresh — the autoload GameState handler grants against the
#       real ledger separately, and try_grant_bundle's replay guard keeps
#       both paths from double-crediting when they target the same ledger.
#
# Dependencies (ledger, skill_inventory, paid_unlocks, billing) default to
# the GameState / BillingManager autoloads. Tests inject local instances via
# setup() so the purchase logic can be exercised without booting the full
# autoload stack.

const CHARACTER_CREATION_SCENE := "res://scenes/character_creation.tscn"
const ERROR_AUTO_HIDE_SECONDS := 3.0

@onready var _gold_label: Label = $MarginContainer/Layout/CurrencyRow/GoldLabel
@onready var _gem_label: Label = $MarginContainer/Layout/CurrencyRow/GemLabel
@onready var _item_list: VBoxContainer = $MarginContainer/Layout/Scroll/ItemList
@onready var _back_btn: Button = $MarginContainer/Layout/BackButton
@onready var error_label: Label = $MarginContainer/Layout/ErrorLabel

var _ledger_override: CurrencyLedger = null
var _skill_inventory_override = null
var _paid_unlocks_override: PaidUnlockInventory = null
var _billing_override = null
var _character_override: CharacterData = null

# product_id -> HBoxContainer row. Lets _refresh_row mutate a single row
# (Buy → Owned) after a successful grant without rebuilding the whole list.
var _rows_by_product: Dictionary = {}

func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	error_label.visible = false
	_refresh_currency()
	_build_item_list()
	var ledger := _ledger()
	if ledger != null and not ledger.balance_changed.is_connected(_on_balance_changed):
		ledger.balance_changed.connect(_on_balance_changed)
	var billing = _billing()
	if billing != null:
		if billing.has_signal("purchase_succeeded") \
				and not billing.purchase_succeeded.is_connected(_on_billing_purchase_succeeded):
			billing.purchase_succeeded.connect(_on_billing_purchase_succeeded)
		if billing.has_signal("purchase_failed") \
				and not billing.purchase_failed.is_connected(_on_billing_purchase_failed):
			billing.purchase_failed.connect(_on_billing_purchase_failed)

# Dependency injection seam for tests. Each param is optional; null falls
# through to the GameState / BillingManager autoload lookups so production
# call sites that instance the scene directly keep working unchanged.
func setup(ledger: CurrencyLedger, skill_inventory, paid_unlocks: PaidUnlockInventory,
		billing = null, character: CharacterData = null) -> void:
	_ledger_override = ledger
	_skill_inventory_override = skill_inventory
	_paid_unlocks_override = paid_unlocks
	_billing_override = billing
	_character_override = character
	if is_inside_tree():
		_refresh_currency()
		_rebuild_item_list()

func _ledger() -> CurrencyLedger:
	if _ledger_override != null:
		return _ledger_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.currency_ledger

func _skill_inventory():
	if _skill_inventory_override != null:
		return _skill_inventory_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.skill_inventory

func _paid_unlocks() -> PaidUnlockInventory:
	if _paid_unlocks_override != null:
		return _paid_unlocks_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.paid_unlocks

func _billing():
	if _billing_override != null:
		return _billing_override
	return get_node_or_null("/root/BillingManager")

func _character() -> CharacterData:
	if _character_override != null:
		return _character_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.current_character

func _on_balance_changed(_currency: int, _new_balance: int) -> void:
	_refresh_currency()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_CREATION_SCENE)

func _refresh_currency() -> void:
	if _gold_label == null or _gem_label == null:
		return
	var ledger := _ledger()
	var gold := ledger.balance(CurrencyLedger.Currency.GOLD) if ledger != null else 0
	var gems := ledger.balance(CurrencyLedger.Currency.GEM) if ledger != null else 0
	_gold_label.text = "Gold: %d" % gold
	_gem_label.text = "Gems: %d" % gems

func _build_item_list() -> void:
	_rows_by_product.clear()
	var current_category := ""
	for item: ShopCatalogItem in ShopCatalog.items():
		if item.category != current_category:
			current_category = item.category
			_add_category_header(current_category)
		_add_item_row(item)

func _rebuild_item_list() -> void:
	if _item_list == null:
		return
	for child in _item_list.get_children():
		child.queue_free()
	_build_item_list()

func _add_category_header(category: String) -> void:
	var label := Label.new()
	label.text = _category_display_name(category)
	label.add_theme_font_size_override("font_size", 16)
	_item_list.add_child(label)
	_item_list.add_child(HSeparator.new())

func _add_item_row(item: ShopCatalogItem) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_desc := VBoxContainer.new()
	name_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = item.display_name
	name_desc.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = item.description
	desc_label.modulate = Color(0.7, 0.7, 0.7, 1)
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.autowrap_mode = 3
	name_desc.add_child(desc_label)

	row.add_child(name_desc)

	var price_label := Label.new()
	if item.category == ShopCatalogItem.CATEGORY_GEM_BUNDLE:
		price_label.text = "$%.2f" % (item.price / 100.0)
	elif item.currency_type == CurrencyLedger.Currency.GOLD:
		price_label.text = "%d G" % item.price
	else:
		price_label.text = "%d Gems" % item.price
	row.add_child(price_label)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(72, 0)
	# Capture the product_id by value via .bind so a single handler covers
	# every row without a per-row lambda allocation.
	btn.pressed.connect(_on_buy_pressed.bind(item.product_id))
	row.add_child(btn)

	_item_list.add_child(row)
	_rows_by_product[item.product_id] = row
	_apply_button_state(row, item)

# Refreshes the Buy/Owned label + disabled flag for the given row. Pulled out
# so post-purchase row updates don't have to rebuild the whole list.
func _apply_button_state(row: HBoxContainer, item: ShopCatalogItem) -> void:
	var btn: Button = null
	for c in row.get_children():
		if c is Button:
			btn = c
			break
	if btn == null:
		return
	if _is_owned(item):
		btn.text = "Owned"
		btn.disabled = true
	else:
		btn.text = "Buy"
		btn.disabled = false

# Public for test injection — the issue's red-green-refactor sketches call
# this directly with a product_id rather than going through a button press.
func _on_buy_pressed(product_id: String) -> void:
	var item := ShopCatalog.find(product_id)
	if item == null:
		return
	if _is_owned(item):
		return
	if item.category == ShopCatalogItem.CATEGORY_GEM_BUNDLE:
		_start_bundle_purchase(product_id)
		return
	var ledger := _ledger()
	if ledger == null:
		return
	# Soft-currency path: debit first; bail if insufficient funds (no error
	# label — PRD calls for a silent / disabled affordance, not a popup).
	if not ledger.debit(item.price, item.currency_type):
		return
	var granted := PurchaseGrantHandler.handle(
		product_id, _character(), null,
		_paid_unlocks(), ledger, _skill_inventory())
	if granted:
		_refresh_row(product_id)
	else:
		# Rare path — debit succeeded but the grant didn't land (e.g. a class
		# upgrade product whose target tier isn't wired in ClassTierUpgrade
		# yet). Refund so the player isn't out the currency for a no-op.
		ledger.credit(item.price, item.currency_type)

func _start_bundle_purchase(product_id: String) -> void:
	var billing = _billing()
	if billing == null:
		return
	billing.start_purchase(product_id)

func _on_billing_purchase_succeeded(product_id: String) -> void:
	var ledger := _ledger()
	if ledger == null:
		return
	# GameState's autoload handler also routes purchase_succeeded through
	# PurchaseGrantHandler; calling it again here is the seam tests need to
	# verify a ledger credit landed without booting GameState, and the
	# replay guard inside try_grant_bundle makes the duplicate prod call a
	# no-op on the same ledger instance.
	PurchaseGrantHandler.handle(
		product_id, _character(), null,
		_paid_unlocks(), ledger, _skill_inventory())
	_refresh_currency()
	_refresh_row(product_id)

func _on_billing_purchase_failed(_product_id: String) -> void:
	_show_error("Purchase failed — try again")

func _show_error(text: String) -> void:
	if error_label == null:
		return
	error_label.text = text
	error_label.visible = true
	get_tree().create_timer(ERROR_AUTO_HIDE_SECONDS).timeout.connect(_hide_error)

func _hide_error() -> void:
	if error_label != null:
		error_label.visible = false

func _refresh_row(product_id: String) -> void:
	if not _rows_by_product.has(product_id):
		return
	var row: HBoxContainer = _rows_by_product[product_id]
	var item := ShopCatalog.find(product_id)
	if item == null:
		return
	_apply_button_state(row, item)

func _is_owned(item: ShopCatalogItem) -> bool:
	var character := _character()
	var paid_unlocks := _paid_unlocks()
	var skill_inventory = _skill_inventory()
	match item.category:
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE:
			if character == null:
				return false
			var source_class := PurchaseRegistry.class_for_product(item.product_id)
			if source_class < 0:
				return false
			return int(character.character_class) == ClassTierUpgrade.target_for(source_class)
		ShopCatalogItem.CATEGORY_CLASS_UNLOCK:
			if paid_unlocks == null:
				return false
			var class_id := PurchaseRegistry.class_id_for_unlock(item.product_id)
			if class_id == "":
				return false
			return paid_unlocks.has_unlock(class_id)
		ShopCatalogItem.CATEGORY_SKILL:
			if skill_inventory == null:
				return false
			var skill_id := PurchaseRegistry.skill_id_for_unlock(item.product_id)
			if skill_id == "":
				return false
			return skill_inventory.has_skill(skill_id)
		ShopCatalogItem.CATEGORY_GEM_BUNDLE:
			return false
	return false

func _category_display_name(category: String) -> String:
	match category:
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE: return "Class Upgrades"
		ShopCatalogItem.CATEGORY_CLASS_UNLOCK: return "Class Unlocks"
		ShopCatalogItem.CATEGORY_SKILL: return "Skills"
		ShopCatalogItem.CATEGORY_GEM_BUNDLE: return "Gem Bundles"
	return category
