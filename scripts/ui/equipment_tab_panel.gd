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

const _CharacterAvatarScript := preload("res://scripts/ui/character_avatar.gd")

# Small square thumbnail next to weapon rows (PRD #268 / issue #271).
# Sized to match the row's text height so it doesn't dominate the row.
const _THUMB_SIZE := Vector2(24, 24)

# Square size of each equipped-slot tile in the horizontal strip.
const _TILE_SIZE := Vector2(36, 36)

# Fixed-width gutter on each bag row reserved for the "Nx" quantity prefix.
# Always present (empty text for single items) so stacked and non-stacked
# rows align — the quantity never shifts the thumbnail/text to the right.
const _QTY_GUTTER_WIDTH := 28.0

# Small font for the "Equipped" / "Bag" section labels so they don't eat
# the tiny ~100px tab height.
const _SECTION_FONT_SIZE := 10

# Tile abbreviation font — small enough that "Wpn"/"Arm"/"Acc" fits inside a
# 36px tile instead of overflowing into the neighbouring tile.
const _TILE_LABEL_FONT_SIZE := 9

# Short labels shown on a tile when it has no thumbnail (empty slot, or an
# armor/accessory item that has no image yet).
const _SLOT_ABBREV := {
	ItemData.Slot.WEAPON: "Wpn",
	ItemData.Slot.ARMOR: "Arm",
	ItemData.Slot.ACCESSORY: "Acc",
}

# Tile backgrounds: a filled slot reads brighter than an empty one, and the
# filled border is rarity-coloured so an equipped (even art-less) item is
# obviously occupied. Empty slots get a dim bg + faint border.
const _TILE_BG_FILLED := Color(0.14, 0.17, 0.24, 0.95)
const _TILE_BG_EMPTY := Color(0.08, 0.09, 0.12, 0.6)
const _TILE_BORDER_EMPTY := Color(0.42, 0.45, 0.52, 0.5)
const _TILE_LABEL_FILLED := Color(1, 1, 1, 0.95)
const _TILE_LABEL_EMPTY := Color(0.62, 0.64, 0.7, 0.7)

var _inventory: ItemInventory = null
var _character: CharacterData = null
# Which equipped-slot rows are currently expanded to reveal their
# Unequip button. Keyed by slot int. Reset on every refresh so opening
# the panel fresh always shows compact rows.
var _expanded: Dictionary = {}
# Persistent two-column skeleton, built once and preserved across every
# _rebuild() so the avatar's loadout_changed subscription survives. Left
# column holds the avatar; right column stacks the equipped slots above the
# bag. The bag is laid out at its full natural height (no inner scroll) —
# the whole Character submenu scrolls as one page via the outer TabScroll,
# so the bag list is no longer trapped in a cramped ~24px window.
# Untyped because Godot's headless parser may resolve this script before
# CharacterAvatar's class_name has been registered project-wide; the script
# is loaded via the _CharacterAvatarScript preload above instead.
var _avatar = null
var _layout: HBoxContainer = null
var _equipped_box: VBoxContainer = null
var _bag_box: VBoxContainer = null

func refresh(inventory: ItemInventory, character: CharacterData) -> void:
	_inventory = inventory
	_character = character
	_expanded.clear()
	_ensure_skeleton()
	if _avatar != null:
		var cc: int = character.character_class if character != null else -1
		_avatar.bind(cc, inventory)
	_rebuild()

# Builds the persistent column structure exactly once. The dynamic rows
# live inside _equipped_box / _bag_box, which _rebuild() repopulates; the
# skeleton and the avatar are never freed, so signal wiring is stable.
func _ensure_skeleton() -> void:
	if _layout != null:
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_layout = HBoxContainer.new()
	_layout.name = "ItemsLayout"
	_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 8)
	add_child(_layout)

	var avatar_col := VBoxContainer.new()
	avatar_col.name = "AvatarColumn"
	# Pin to top so a tall bag doesn't push the avatar to the middle of the
	# scroll region — with a long inventory the avatar would otherwise be
	# centered against the full content height.
	avatar_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	avatar_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_avatar = _CharacterAvatarScript.new()
	_avatar.name = "CharacterAvatar"
	_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar_col.add_child(_avatar)
	_layout.add_child(avatar_col)

	var menu_col := VBoxContainer.new()
	menu_col.name = "MenuColumn"
	menu_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_child(menu_col)

	# Equipped strip + the "Bag" header.
	_equipped_box = VBoxContainer.new()
	_equipped_box.name = "EquippedSection"
	_equipped_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipped_box.add_theme_constant_override("separation", 2)
	menu_col.add_child(_equipped_box)

	# Bag list, laid out at full natural height directly in the column. No
	# inner ScrollContainer: the outer TabScroll scrolls the whole page, so
	# the bag stays put and grows as tall as its contents need.
	_bag_box = VBoxContainer.new()
	_bag_box.name = "BagSection"
	_bag_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_col.add_child(_bag_box)

# Repopulates the equipped slots and bag list. The skeleton/avatar persist;
# only the dynamic rows inside _equipped_box / _bag_box are rebuilt.
func _rebuild() -> void:
	# queue_free (not free) so a rebuild triggered from a child Button's
	# pressed signal doesn't free that Button mid-emission — Godot errors
	# with "Object was freed or unreferenced while a signal is being
	# emitted from it" on the synchronous free path.
	_clear_children(_equipped_box)
	_clear_children(_bag_box)
	_build_equipped_section()
	_add_section_label(_equipped_box, "Bag")
	_bag_box.add_child(_make_bag_list())

# Equipped slots render as one compact row: the "Equipped" label followed by
# three icon tiles. Tapping a filled tile toggles a one-line detail row
# (name + Unequip) beneath the strip; only one slot is expanded at a time so
# the pinned region stays short and the bag keeps most of the height.
func _build_equipped_section() -> void:
	var strip := HBoxContainer.new()
	strip.name = "EquippedStrip"
	strip.add_theme_constant_override("separation", 6)
	var heading := Label.new()
	heading.name = "Section_Equipped"
	heading.text = "Equipped"
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", _SECTION_FONT_SIZE)
	strip.add_child(heading)
	for entry in SLOTS:
		strip.add_child(_make_slot_tile(entry["slot"], entry["label"]))
	_equipped_box.add_child(strip)
	for entry in SLOTS:
		var slot: int = entry["slot"]
		if not _expanded.get(slot, false):
			continue
		var item: ItemData = _inventory.equipped_in(slot) if _inventory != null else null
		if item != null:
			_equipped_box.add_child(_make_equipped_detail(slot, entry["label"], item))

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _add_section_label(parent: Node, text: String) -> void:
	var l := Label.new()
	l.name = "Section_" + text
	l.text = text
	l.add_theme_font_size_override("font_size", _SECTION_FONT_SIZE)
	parent.add_child(l)

# One equipped-slot tile. Weapons show their resolver thumbnail; empty
# slots and (image-less) armor/accessory show a short text abbreviation.
# The full name/rarity/bonus lives in the tooltip and in the expand detail.
func _make_slot_tile(slot: int, slot_label: String) -> Control:
	var item: ItemData = _inventory.equipped_in(slot) if _inventory != null else null
	var filled := item != null
	var tile := Button.new()
	tile.name = "SlotTile_%d" % slot
	tile.custom_minimum_size = _TILE_SIZE
	# Empty slots are inert (disabled, not hidden) so the strip keeps a
	# stable three-tile shape regardless of what's equipped.
	tile.disabled = not filled
	tile.tooltip_text = _slot_tooltip(slot_label, item)
	# Exposed for tests + a quick read of occupancy without inspecting styling.
	tile.set_meta("equipped", filled)
	_style_tile(tile, item)
	var thumb := _make_thumbnail("SlotThumb_%d" % slot, item)
	if thumb != null:
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(thumb)
	else:
		var lbl := Label.new()
		lbl.name = "SlotTileLabel_%d" % slot
		lbl.text = _SLOT_ABBREV.get(slot, "?")
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", _TILE_LABEL_FONT_SIZE)
		lbl.add_theme_color_override("font_color", _TILE_LABEL_FILLED if filled else _TILE_LABEL_EMPTY)
		tile.add_child(lbl)
	var slot_id := slot
	tile.pressed.connect(func(): _on_slot_tile_pressed(slot_id))
	return tile

# Paints the tile so a filled slot (brighter bg, rarity-coloured border) is
# unmistakably distinct from an empty one (dim bg, faint border) — even when
# the item has no thumbnail yet. The same style is applied to every button
# state so hover/pressed/disabled don't revert to the default theme look.
func _style_tile(tile: Button, item: ItemData) -> void:
	var filled := item != null
	var sb := StyleBoxFlat.new()
	sb.bg_color = _TILE_BG_FILLED if filled else _TILE_BG_EMPTY
	sb.set_border_width_all(2 if filled else 1)
	sb.border_color = _rarity_color(item.rarity) if filled else _TILE_BORDER_EMPTY
	sb.set_corner_radius_all(3)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		tile.add_theme_stylebox_override(state, sb)

func _rarity_color(rarity: int) -> Color:
	return ItemDisplayFormatter.RARITY_COLORS.get(rarity, ItemDisplayFormatter.RARITY_COLORS[ItemData.Rarity.COMMON])

func _slot_tooltip(slot_label: String, item: ItemData) -> String:
	if item == null:
		return "%s: Empty" % slot_label
	# Multi-line, no " — " or "(Rarity)" parenthetical — see PRD #292.
	var parts: Array[String] = ["%s: %s" % [slot_label, ItemDisplayFormatter.display_name(item)],
		ItemDisplayFormatter.rarity_label(item)]
	for line in ItemDisplayFormatter.bonus_lines(item):
		parts.append(line)
	return "\n".join(parts)

# Vertical stack: name / tinted rarity / one label per bonus. Used by both
# the bag rows and the equipped tap-to-expand detail so they share an
# identical layout (PRD #292 acceptance criteria).
func _build_item_text_column(prefix: String, item: ItemData) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "%sText" % prefix
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)

	var name_lbl := Label.new()
	name_lbl.name = "%sName" % prefix
	name_lbl.text = ItemDisplayFormatter.display_name(item)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wrap long names across multiple lines rather than ellipsizing — the
	# PRD explicitly forbids name truncation.
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_lbl)

	var rarity_lbl := Label.new()
	rarity_lbl.name = "%sRarity" % prefix
	rarity_lbl.text = ItemDisplayFormatter.rarity_label(item)
	rarity_lbl.add_theme_color_override("font_color", ItemDisplayFormatter.rarity_color(item))
	col.add_child(rarity_lbl)

	var lines := ItemDisplayFormatter.bonus_lines(item)
	for i in lines.size():
		var bonus_lbl := Label.new()
		bonus_lbl.name = "%sBonus_%d" % [prefix, i]
		bonus_lbl.text = lines[i]
		col.add_child(bonus_lbl)
	return col

func _make_equipped_detail(slot: int, _slot_label: String, item: ItemData) -> Control:
	var row := HBoxContainer.new()
	row.name = "EquippedDetail_%d" % slot
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(_build_item_text_column("EquippedDetail_%d_" % slot, item))
	var btn := Button.new()
	btn.name = "UnequipButton_%d" % slot
	btn.text = "Unequip"
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var slot_id := slot
	btn.pressed.connect(func(): _on_unequip_pressed(slot_id))
	row.add_child(btn)
	return row

# Bag items live in a plain VBoxContainer in the right column (see
# _ensure_skeleton). It grows to its full content height; the outer
# TabScroll scrolls the whole page when the loadout runs long.
# Duplicate items (same id) collapse into one row with a "Nx" quantity
# prefix — the Equip button still equips a single instance because
# _on_equip_pressed removes the first match by id from the bag.
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
	var groups := _group_bag_items(items)
	for i in groups.size():
		var g: Dictionary = groups[i]
		list.add_child(_make_bag_row(g["item"], i, int(g["count"])))
	return list

# Collapses duplicate bag items (same id) into one entry preserving the
# first-seen order. Returns [{item: ItemData, count: int}, ...].
func _group_bag_items(items: Array[ItemData]) -> Array:
	var out: Array = []
	var index_by_id: Dictionary = {}
	for it in items:
		if index_by_id.has(it.id):
			var idx: int = index_by_id[it.id]
			out[idx]["count"] = int(out[idx]["count"]) + 1
		else:
			index_by_id[it.id] = out.size()
			out.append({"item": it, "count": 1})
	return out

func _make_bag_row(item: ItemData, index: int, count: int = 1) -> Control:
	var row := HBoxContainer.new()
	row.name = "BagRow_%d" % index
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	# Always reserve a fixed-width gutter for the quantity so a "2x" prefix
	# on a stacked row doesn't shift the thumbnail/text to the right of
	# single-item rows — every bag row's content starts at the same x.
	var qty := Label.new()
	qty.name = "BagQty_%d" % index
	qty.text = "%dx" % count if count > 1 else ""
	qty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty.custom_minimum_size = Vector2(_QTY_GUTTER_WIDTH, 0)
	qty.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(qty)
	var thumb := _make_thumbnail("BagThumb_%d" % index, item)
	if thumb != null:
		thumb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(thumb)
	row.add_child(_build_item_text_column("Bag_%d_" % index, item))
	var btn := Button.new()
	btn.name = "EquipButton_%d" % index
	btn.text = "Equip"
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var item_id := item.id
	btn.pressed.connect(func(): _on_equip_pressed(item_id))
	row.add_child(btn)
	return row

func _on_slot_tile_pressed(slot: int) -> void:
	if _inventory == null or _inventory.equipped_in(slot) == null:
		return
	# Single-expand: tapping a tile opens its detail and closes any other.
	# Tapping the already-open tile closes it.
	var was_open: bool = _expanded.get(slot, false)
	_expanded.clear()
	if not was_open:
		_expanded[slot] = true
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
