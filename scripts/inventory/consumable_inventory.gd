class_name ConsumableInventory
extends RefCounted

# Tracks per-type counts of consumable items (PRD #358 / slice 1). Separate
# from gear-only ItemInventory because potions are stackable by string id and
# don't equip into a slot. Mirrors CurrencyLedger's serialize/deserialize style.

const STACK_CAP := 99

signal inventory_changed

var _counts: Dictionary = {}

func count_of(potion_id: String) -> int:
	return int(_counts.get(potion_id, 0))

func add(potion_id: String, amount: int) -> void:
	if potion_id == "" or amount <= 0:
		return
	var next: int = mini(count_of(potion_id) + amount, STACK_CAP)
	_counts[potion_id] = next
	inventory_changed.emit()

# Returns true and decrements on success; false and no mutation when the id is
# missing or already at 0. Mirrors CurrencyLedger.debit's no-mutation-on-fail
# contract so callers can use it as the gate for "did the potion fire?".
func consume(potion_id: String) -> bool:
	var current := count_of(potion_id)
	if current <= 0:
		return false
	_counts[potion_id] = current - 1
	inventory_changed.emit()
	return true

func serialize() -> Dictionary:
	return _counts.duplicate()

func deserialize(data: Variant) -> void:
	_counts.clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in data.keys():
		var v := int(data[k])
		if v > 0:
			_counts[String(k)] = mini(v, STACK_CAP)
