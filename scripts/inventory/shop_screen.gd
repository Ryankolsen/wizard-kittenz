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

# Fired on every Back press. Overlay callers (e.g. the in-dungeon bar room)
# connect this to tear the shop down without a scene change; the legacy
# character-creation flow ignores it and relies on the default scene swap.
signal back_pressed()
# Fired once from _flash_row when a row is flashed after a successful purchase.
# Tests assert against this signal rather than the tween itself (PRD #231 §UX).
signal row_flashed(product_id)

const _FLASH_DURATION := 0.25
const _FLASH_TINT := Color(1.6, 1.6, 1.6, 1.0)
# When true, _on_back_pressed skips the scene change so an overlay host can
# decide how to dispose the screen (queue_free its CanvasLayer wrapper, etc.).
var _overlay_mode: bool = false


func set_overlay_mode(enabled: bool) -> void:
	_overlay_mode = enabled

@onready var _gold_label: Label = $MarginContainer/Layout/CurrencyRow/GoldLabel
@onready var _gem_label: Label = $MarginContainer/Layout/CurrencyRow/GemLabel
@onready var _item_list: VBoxContainer = $MarginContainer/Layout/Scroll/ScrollPadding/ItemList
@onready var _back_btn: Button = $MarginContainer/Layout/BackButton
@onready var error_label: Label = $MarginContainer/Layout/ErrorLabel

var _ledger_override: CurrencyLedger = null
var _skill_inventory_override = null
var _paid_unlocks_override: PaidUnlockInventory = null
var _billing_override = null
var _character_override: CharacterData = null
var _item_inventory_override: ItemInventory = null

# product_id -> HBoxContainer row. Lets _refresh_row mutate a single row
# (Buy → Owned) after a successful grant without rebuilding the whole list.
var _rows_by_product: Dictionary = {}

func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	error_label.visible = false
	_refresh_currency()
	_build_item_list()
	_connect_dependency_signals()

# Wires the ledger + billing signals against whatever provider lookups return
# right now. Called from _ready (production) and from setup (tests, where the
# override ledger only exists after setup runs).
func _connect_dependency_signals() -> void:
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
	var inv := _item_inventory()
	if inv != null and not inv.inventory_changed.is_connected(_on_inventory_changed):
		inv.inventory_changed.connect(_on_inventory_changed)

# Dependency injection seam for tests. Each param is optional; null falls
# through to the GameState / BillingManager autoload lookups so production
# call sites that instance the scene directly keep working unchanged.
func setup(ledger: CurrencyLedger, skill_inventory, paid_unlocks: PaidUnlockInventory,
		billing = null, character: CharacterData = null,
		item_inventory: ItemInventory = null) -> void:
	_ledger_override = ledger
	_skill_inventory_override = skill_inventory
	_paid_unlocks_override = paid_unlocks
	_billing_override = billing
	_character_override = character
	_item_inventory_override = item_inventory
	if is_inside_tree():
		_refresh_currency()
		_rebuild_item_list()
		_connect_dependency_signals()

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

func _item_inventory() -> ItemInventory:
	if _item_inventory_override != null:
		return _item_inventory_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.item_inventory

func _character_class() -> int:
	var c := _character()
	if c == null:
		return -1
	return int(c.character_class)

func _on_balance_changed(_currency: int, _new_balance: int) -> void:
	_refresh_currency()
	# Affordability is per-row state, so any balance change has to re-run the
	# button rule across every row — not just the currency labels at the top.
	_refresh_all_rows()

func _on_inventory_changed() -> void:
	# Gear ownership (Owned vs Buy) is sourced from ItemInventory, so any bag
	# or equipped-slot mutation has to re-run the button rule across rows.
	_refresh_all_rows()

func _on_back_pressed() -> void:
	back_pressed.emit()
	if _overlay_mode:
		return
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
	for item: ShopCatalogItem in ShopCatalog.items(_character_class()):
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

	if item.category == ShopCatalogItem.CATEGORY_GEAR:
		# Broken-up layout (PRD #292 / Slice 3): tinted rarity word on its own
		# line, then one Label per humanized bonus. Mirrors the equipped-detail
		# stack so a player sees the same shape in the shop and the bag.
		var rarity_label := Label.new()
		rarity_label.text = ItemDisplayFormatter.RARITY_LABELS.get(item.rarity, "")
		rarity_label.add_theme_color_override("font_color",
			ItemDisplayFormatter.RARITY_COLORS.get(item.rarity,
				ItemDisplayFormatter.RARITY_COLORS[ItemData.Rarity.COMMON]))
		rarity_label.add_theme_font_size_override("font_size", 11)
		name_desc.add_child(rarity_label)
		for line in item.bonus_lines:
			var bonus_label := Label.new()
			bonus_label.text = line
			bonus_label.add_theme_font_size_override("font_size", 11)
			name_desc.add_child(bonus_label)
	else:
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
		btn.disabled = not _can_afford(item)

# Gem bundles are paid via the billing platform, not the in-game ledger, so
# they're always "affordable" from the shop's perspective.
func _can_afford(item: ShopCatalogItem) -> bool:
	if item.category == ShopCatalogItem.CATEGORY_GEM_BUNDLE:
		return true
	var ledger := _ledger()
	if ledger == null:
		return false
	return ledger.balance(item.currency_type) >= item.price

func _refresh_all_rows() -> void:
	for product_id in _rows_by_product.keys():
		var row: HBoxContainer = _rows_by_product[product_id]
		var item := ShopCatalog.find(product_id)
		if item == null:
			continue
		_apply_button_state(row, item)

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
		_paid_unlocks(), ledger, _skill_inventory(), _item_inventory())
	if granted:
		_refresh_row(product_id)
		if _rows_by_product.has(product_id):
			_flash_row(_rows_by_product[product_id])
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
		_paid_unlocks(), ledger, _skill_inventory(), _item_inventory())
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

# Briefly tweens the row's modulate to a brighter tint and back so the player
# sees which row landed after a purchase. Pure visual feedback — emits
# row_flashed for tests since tween-driven changes are awkward to assert on.
func _flash_row(row: HBoxContainer) -> void:
	if row == null:
		return
	var product_id := ""
	for pid in _rows_by_product.keys():
		if _rows_by_product[pid] == row:
			product_id = pid
			break
	row_flashed.emit(product_id)
	if not row.is_inside_tree():
		return
	var tween := row.create_tween()
	tween.tween_property(row, "modulate", _FLASH_TINT, _FLASH_DURATION * 0.5)
	tween.tween_property(row, "modulate", Color(1, 1, 1, 1), _FLASH_DURATION * 0.5)

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
		ShopCatalogItem.CATEGORY_GEAR:
			# Per PRD #231: a gear row is Owned iff the item is currently
			# in the bag OR equipped in any slot. Players re-buy after the
			# item leaves inventory (dropped, consumed, etc.).
			var inv := _item_inventory()
			if inv == null:
				return false
			for it in inv.bag_items():
				if it != null and it.id == item.product_id:
					return true
			for slot in [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.ACCESSORY]:
				var equipped := inv.equipped_in(slot)
				if equipped != null and equipped.id == item.product_id:
					return true
			return false
	return false

func _category_display_name(category: String) -> String:
	match category:
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE: return "Class Upgrades"
		ShopCatalogItem.CATEGORY_CLASS_UNLOCK: return "Class Unlocks"
		ShopCatalogItem.CATEGORY_SKILL: return "Skills"
		ShopCatalogItem.CATEGORY_GEM_BUNDLE: return "Gem Bundles"
		ShopCatalogItem.CATEGORY_GEAR: return "Gear"
	return category
