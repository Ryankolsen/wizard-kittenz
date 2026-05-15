class_name EquipmentTabPanel
extends VBoxContainer

# Equipment panel inside the pause menu's Character → Inventory tab
# (PRD #73 / issue #82). Programmatically builds three equipped-slot rows
# (Weapon / Armor / Accessory) and a list of bag items, all driven off
# GameState.item_inventory. Mutations go through ItemInventory methods.
#
# Stat math: HUD's loot-prompt handler (#80) inlines +/- bonus on
# CharacterData by stat_name rather than calling
# ItemStatApplicator.recompute, because the codebase has no persisted
# base CharacterData snapshot to recompute against. This panel uses the
# same inline approach so equip / unequip / swap all produce a single
# net delta — matching the existing pattern and keeping a future "store
# base snapshot, switch to recompute" change to one place.

const SLOTS := [
	{"slot": ItemData.Slot.WEAPON, "label": "Weapon"},
	{"slot": ItemData.Slot.ARMOR, "label": "Armor"},
	{"slot": ItemData.Slot.ACCESSORY, "label": "Accessory"},
]

const RARITY_NAMES := {
	ItemData.Rarity.COMMON: "Common",
	ItemData.Rarity.RARE: "Rare",
	ItemData.Rarity.EPIC: "Epic",
}

var _inventory: ItemInventory = null
var _character: CharacterData = null
# Which equipped-slot rows are currently expanded to reveal their
# Unequip button. Keyed by slot int. Reset on every refresh so opening
# the panel fresh always shows compact rows.
var _expanded: Dictionary = {}

func refresh(inventory: ItemInventory, character: CharacterData) -> void:
	_inventory = inventory
	_character = character
	_expanded.clear()
	_rebuild()

# Bound to ItemInventory.loadout_changed so external mutations (loot
# prompt, save load) reflect immediately if the panel is open. Caller
# binds via refresh() — the panel deliberately doesn't manage the
# connection lifecycle itself, so a stale instance never holds a
# reference to a freed inventory.
func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_add_section_label("Equipped")
	for entry in SLOTS:
		add_child(_make_slot_row(entry["slot"], entry["label"]))
	_add_section_label("Bag")
	add_child(_make_bag_list())

func _add_section_label(text: String) -> void:
	var l := Label.new()
	l.name = "Section_" + text
	l.text = text
	add_child(l)

func _make_slot_row(slot: int, slot_label: String) -> Control:
	var col := VBoxContainer.new()
	col.name = "SlotCol_%d" % slot
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.name = "SlotRow_%d" % slot
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var item: ItemData = _inventory.equipped_in(slot) if _inventory != null else null
	var label := Button.new()
	label.name = "SlotLabel_%d" % slot
	label.flat = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item == null:
		label.text = "%s: Empty" % slot_label
	else:
		label.text = "%s: %s (%s) — %s" % [slot_label, item.display_name, _rarity_name(item.rarity), _stat_desc(item)]
	# Tapping the row toggles an Unequip button for filled slots only —
	# empty slots are inert. Disabled (rather than hidden) on empty so
	# the row's hit area stays consistent across states.
	label.disabled = item == null
	var slot_id := slot
	label.pressed.connect(func(): _on_slot_row_pressed(slot_id))
	row.add_child(label)
	col.add_child(row)
	if item != null and _expanded.get(slot, false):
		var unequip_btn := Button.new()
		unequip_btn.name = "UnequipButton_%d" % slot
		unequip_btn.text = "Unequip"
		unequip_btn.pressed.connect(func(): _on_unequip_pressed(slot_id))
		col.add_child(unequip_btn)
	return col

func _make_bag_list() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "BagScroll"
	scroll.custom_minimum_size = Vector2(0, 80)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.name = "BagList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if _inventory == null:
		return scroll
	var items := _inventory.bag_items()
	if items.is_empty():
		var empty := Label.new()
		empty.name = "BagEmpty"
		empty.text = "Bag is empty"
		list.add_child(empty)
		return scroll
	for i in items.size():
		list.add_child(_make_bag_row(items[i], i))
	return scroll

func _make_bag_row(item: ItemData, index: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "BagRow_%d" % index
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.name = "BagLabel_%d" % index
	label.text = "%s (%s) — %s" % [item.display_name, _rarity_name(item.rarity), _stat_desc(item)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var btn := Button.new()
	btn.name = "EquipButton_%d" % index
	btn.text = "Equip"
	var item_id := item.id
	btn.pressed.connect(func(): _on_equip_pressed(item_id))
	row.add_child(btn)
	return row

func _on_slot_row_pressed(slot: int) -> void:
	if _inventory == null or _inventory.equipped_in(slot) == null:
		return
	_expanded[slot] = not _expanded.get(slot, false)
	_rebuild()

func _on_equip_pressed(item_id: String) -> void:
	if _inventory == null:
		return
	var item: ItemData = _find_bag_item(item_id)
	if item == null:
		return
	var prev: ItemData = _inventory.equipped_in(item.slot)
	if prev != null and _character != null:
		_character.apply_stat_delta(prev.stat_name, -prev.stat_bonus)
	_inventory.remove_from_bag(item_id)
	_inventory.equip(item)
	if _character != null:
		_character.apply_stat_delta(item.stat_name, item.stat_bonus)
	_expanded.clear()
	_rebuild()

func _on_unequip_pressed(slot: int) -> void:
	if _inventory == null:
		return
	var item: ItemData = _inventory.equipped_in(slot)
	if item == null:
		return
	if _character != null:
		_character.apply_stat_delta(item.stat_name, -item.stat_bonus)
	_inventory.unequip(slot)
	_expanded.clear()
	_rebuild()

func _find_bag_item(item_id: String) -> ItemData:
	if _inventory == null:
		return null
	for it in _inventory.bag_items():
		if it.id == item_id:
			return it
	return null

func _stat_desc(item: ItemData) -> String:
	if item.stat_name == "":
		return ""
	var bonus := item.stat_bonus
	var formatted: String
	if bonus == int(bonus):
		formatted = "+%d" % int(bonus)
	else:
		formatted = "+%.2f" % bonus
	return "%s %s" % [formatted, item.stat_name]

func _rarity_name(rarity: int) -> String:
	return RARITY_NAMES.get(rarity, "Common")
