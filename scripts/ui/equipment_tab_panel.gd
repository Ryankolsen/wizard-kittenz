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

const _CharacterAvatarScript := preload("res://scripts/ui/character_avatar.gd")

# Small square thumbnail next to weapon rows (PRD #268 / issue #271).
# Sized to match the row's text height so it doesn't dominate the row.
const _THUMB_SIZE := Vector2(24, 24)

var _inventory: ItemInventory = null
var _character: CharacterData = null
# Which equipped-slot rows are currently expanded to reveal their
# Unequip button. Keyed by slot int. Reset on every refresh so opening
# the panel fresh always shows compact rows.
var _expanded: Dictionary = {}
# Sits above the slot rows and renders the player's kitten holding the
# equipped weapon (PRD #268 / issue #270). Created once and preserved
# across _rebuild() so its signal subscription to inventory.loadout_changed
# survives every panel refresh.
# Untyped because Godot's headless parser may resolve this script before
# CharacterAvatar's class_name has been registered project-wide; the script
# is loaded via the _CharacterAvatarScript preload above instead.
var _avatar = null

func refresh(inventory: ItemInventory, character: CharacterData) -> void:
	_inventory = inventory
	_character = character
	_expanded.clear()
	_ensure_avatar()
	if _avatar != null:
		var cc: int = character.character_class if character != null else -1
		_avatar.bind(cc, inventory)
	_rebuild()

func _ensure_avatar() -> void:
	if _avatar != null:
		return
	_avatar = _CharacterAvatarScript.new()
	_avatar.name = "CharacterAvatar"
	add_child(_avatar)
	move_child(_avatar, 0)

# Bound to ItemInventory.loadout_changed so external mutations (loot
# prompt, save load) reflect immediately if the panel is open. Caller
# binds via refresh() — the panel deliberately doesn't manage the
# connection lifecycle itself, so a stale instance never holds a
# reference to a freed inventory.
func _rebuild() -> void:
	# queue_free (not free) so a rebuild triggered from a child Button's
	# pressed signal doesn't free that Button mid-emission — Godot errors
	# with "Object was freed or unreferenced while a signal is being
	# emitted from it" on the synchronous free path.
	for child in get_children():
		if child == _avatar:
			continue
		remove_child(child)
		child.queue_free()
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
	var thumb := _make_thumbnail("SlotThumb_%d" % slot, item)
	if thumb != null:
		row.add_child(thumb)
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

# Bag items live in a plain VBoxContainer — the pause menu's outer
# TabScroll already scrolls all tab content, so a nested ScrollContainer
# here would produce a scroll-bar-inside-a-scroll-bar.
func _make_bag_list() -> Control:
	var list := VBoxContainer.new()
	list.name = "BagList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _inventory == null:
		return list
	var items := _inventory.bag_items()
	if items.is_empty():
		var empty := Label.new()
		empty.name = "BagEmpty"
		empty.text = "Bag is empty"
		list.add_child(empty)
		return list
	for i in items.size():
		list.add_child(_make_bag_row(items[i], i))
	return list

func _make_bag_row(item: ItemData, index: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "BagRow_%d" % index
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var thumb := _make_thumbnail("BagThumb_%d" % index, item)
	if thumb != null:
		row.add_child(thumb)
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
		_apply_item_delta(prev, -1.0)
	_inventory.remove_from_bag(item_id)
	_inventory.equip(item)
	if _character != null:
		_apply_item_delta(item, 1.0)
	_expanded.clear()
	_rebuild()

func _on_unequip_pressed(slot: int) -> void:
	if _inventory == null:
		return
	var item: ItemData = _inventory.equipped_in(slot)
	if item == null:
		return
	if _character != null:
		_apply_item_delta(item, -1.0)
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
	var lines: Array[String] = []
	for bonus in item.bonuses:
		if bonus == null or bonus.stat_name == "":
			continue
		lines.append(_format_bonus(bonus))
	return ", ".join(lines)

func _format_bonus(bonus: StatBonus) -> String:
	var formatted: String
	if bonus.stat_bonus == int(bonus.stat_bonus):
		formatted = "+%d" % int(bonus.stat_bonus)
	else:
		formatted = "+%.2f" % bonus.stat_bonus
	return "%s %s" % [formatted, bonus.stat_name]

func _apply_item_delta(item: ItemData, sign: float) -> void:
	for bonus in item.bonuses:
		if bonus == null or bonus.stat_name == "":
			continue
		CharacterMutator.new(_character).apply_stat_delta(bonus.stat_name, sign * bonus.stat_bonus)

# Returns a TextureRect for the given item's resolver-derived image, or
# null when the item has no resolvable image (armor/accessory/empty slot).
# Routing imagery through ItemImageResolver keeps #269 as the single source
# of truth for item -> texture mapping.
func _make_thumbnail(node_name: String, item: ItemData) -> TextureRect:
	var tex_path := ItemImageResolver.texture_path_for_item(item)
	if tex_path == "":
		return null
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = load(tex_path)
	rect.custom_minimum_size = _THUMB_SIZE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect

func _rarity_name(rarity: int) -> String:
	return RARITY_NAMES.get(rarity, "Common")
