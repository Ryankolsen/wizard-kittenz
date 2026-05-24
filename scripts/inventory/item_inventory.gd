class_name ItemInventory
extends RefCounted

signal loadout_changed
# Fired whenever the bag or any equipped slot mutates. ShopScreen (PRD #231,
# #234) listens so a row's Owned/Buy state stays live without reopening the
# shop. loadout_changed remains scoped to equip/unequip for callers (HUD
# stats, etc.) that only care about the equipped loadout.
signal inventory_changed

var _equipped: Dictionary = {
	ItemData.Slot.WEAPON: null,
	ItemData.Slot.ARMOR: null,
	ItemData.Slot.ACCESSORY: null,
}
var _bag: Array[ItemData] = []

func equip(item: ItemData) -> void:
	if item == null:
		return
	var prev: ItemData = _equipped[item.slot]
	if prev != null:
		_bag.append(prev)
	_equipped[item.slot] = item
	loadout_changed.emit()
	inventory_changed.emit()

func unequip(slot: int) -> void:
	var prev: ItemData = _equipped[slot]
	if prev == null:
		return
	_bag.append(prev)
	_equipped[slot] = null
	loadout_changed.emit()
	inventory_changed.emit()

func add_to_bag(item: ItemData) -> void:
	if item == null:
		return
	_bag.append(item)
	inventory_changed.emit()

func remove_from_bag(item_id: String) -> void:
	for i in _bag.size():
		if _bag[i].id == item_id:
			_bag.remove_at(i)
			inventory_changed.emit()
			return

func equipped_in(slot: int) -> ItemData:
	return _equipped[slot]

func bag_items() -> Array[ItemData]:
	return _bag
