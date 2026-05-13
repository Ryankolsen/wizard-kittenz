class_name ShopScreen
extends Control

const CHARACTER_CREATION_SCENE := "res://scenes/character_creation.tscn"

@onready var _gold_label: Label = $MarginContainer/Layout/CurrencyRow/GoldLabel
@onready var _gem_label: Label = $MarginContainer/Layout/CurrencyRow/GemLabel
@onready var _item_list: VBoxContainer = $MarginContainer/Layout/Scroll/ItemList
@onready var _back_btn: Button = $MarginContainer/Layout/BackButton

func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_refresh_currency()
	_build_item_list()
	var ledger := _ledger()
	if ledger != null:
		ledger.balance_changed.connect(_on_balance_changed)

func _ledger() -> CurrencyLedger:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.currency_ledger

func _on_balance_changed(_currency: int, _new_balance: int) -> void:
	_refresh_currency()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_CREATION_SCENE)

func _refresh_currency() -> void:
	var ledger := _ledger()
	var gold := ledger.balance(CurrencyLedger.Currency.GOLD) if ledger != null else 0
	var gems := ledger.balance(CurrencyLedger.Currency.GEM) if ledger != null else 0
	_gold_label.text = "Gold: %d" % gold
	_gem_label.text = "Gems: %d" % gems

func _build_item_list() -> void:
	var gs := get_node_or_null("/root/GameState")
	var paid_unlocks: PaidUnlockInventory = gs.paid_unlocks if gs != null else PaidUnlockInventory.new()
	var skill_inventory = gs.skill_inventory if gs != null else null
	var character: CharacterData = gs.current_character if gs != null else null

	var current_category := ""
	for item: ShopCatalogItem in ShopCatalog.items():
		if item.category != current_category:
			current_category = item.category
			_add_category_header(current_category)
		_add_item_row(item, character, paid_unlocks, skill_inventory)

func _add_category_header(category: String) -> void:
	var label := Label.new()
	label.text = _category_display_name(category)
	label.add_theme_font_size_override("font_size", 16)
	_item_list.add_child(label)
	_item_list.add_child(HSeparator.new())

func _add_item_row(item: ShopCatalogItem, character: CharacterData,
		paid_unlocks: PaidUnlockInventory, skill_inventory) -> void:
	var owned := _is_owned(item, character, paid_unlocks, skill_inventory)

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
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_ARBITRARY
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
	btn.custom_minimum_size = Vector2(64, 0)
	if owned:
		btn.text = "Owned"
		btn.disabled = true
	else:
		btn.text = "Buy"
	row.add_child(btn)

	_item_list.add_child(row)

func _is_owned(item: ShopCatalogItem, character: CharacterData,
		paid_unlocks: PaidUnlockInventory, skill_inventory) -> bool:
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
			var class_id := item.product_id.replace("class_unlock_", "")
			return paid_unlocks.has_unlock(class_id)
		ShopCatalogItem.CATEGORY_SKILL:
			if skill_inventory == null:
				return false
			return skill_inventory.has_skill(_skill_id_from_product(item.product_id))
		ShopCatalogItem.CATEGORY_GEM_BUNDLE:
			return false
	return false

# "skill_mage_fireball" → "fireball", "skill_ninja_smoke_bomb" → "smoke_bomb"
func _skill_id_from_product(product_id: String) -> String:
	var without_prefix := product_id.substr("skill_".length())
	var first_underscore := without_prefix.find("_")
	if first_underscore < 0:
		return ""
	return without_prefix.substr(first_underscore + 1)

func _category_display_name(category: String) -> String:
	match category:
		ShopCatalogItem.CATEGORY_CLASS_UPGRADE: return "Class Upgrades"
		ShopCatalogItem.CATEGORY_CLASS_UNLOCK: return "Class Unlocks"
		ShopCatalogItem.CATEGORY_SKILL: return "Skills"
		ShopCatalogItem.CATEGORY_GEM_BUNDLE: return "Gem Bundles"
	return category
