class_name PotionBelt
extends RefCounted

# Pure-data 3-slot potion belt (PRD #358 / slice 4). Slots hold potion ids
# (strings) — not PotionDefinitions — so the belt can survive a session
# without a catalog reference and so save/load is trivial. Mirrors Quickbar's
# assign/swap semantics, but a shared cooldown gates every slot's fire instead
# of per-spell cooldowns on each entry.

const SLOT_COUNT := 3
const COOLDOWN_SECONDS := 30.0

signal slot_changed(slot: int)
signal slot_used(slot: int)

var _slots: Array = ["", "", ""]
var _cooldown_remaining: float = 0.0

func get_slot(n: int) -> String:
	if n < 1 or n > SLOT_COUNT:
		return ""
	return _slots[n - 1]

func assign(n: int, potion_id: String) -> void:
	if n < 1 or n > SLOT_COUNT or potion_id == "":
		return
	var target_idx := n - 1
	if _slots[target_idx] == potion_id:
		return
	var existing_idx := _index_of(potion_id)
	if existing_idx != -1:
		var prev: String = _slots[target_idx]
		_slots[target_idx] = potion_id
		_slots[existing_idx] = prev
		slot_changed.emit(existing_idx + 1)
		slot_changed.emit(n)
		return
	_slots[target_idx] = potion_id
	slot_changed.emit(n)

func unassign(n: int) -> void:
	if n < 1 or n > SLOT_COUNT:
		return
	if _slots[n - 1] == "":
		return
	_slots[n - 1] = ""
	slot_changed.emit(n)

func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0

func cooldown_remaining() -> float:
	return _cooldown_remaining

func tick(delta: float) -> void:
	if _cooldown_remaining <= 0.0:
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)

# Fires the potion in slot n: consumes 1 from inventory, applies the effect
# via PotionEffectResolver, starts the shared belt cooldown, and emits
# slot_used(n). Returns false (no mutation) on empty slot, 0-count, or
# active cooldown — the three "harmless mis-tap" cases.
func use_slot(n: int, caster, inventory: ConsumableInventory) -> bool:
	if n < 1 or n > SLOT_COUNT:
		return false
	if is_on_cooldown():
		return false
	var potion_id: String = _slots[n - 1]
	if potion_id == "":
		return false
	if inventory == null or inventory.count_of(potion_id) <= 0:
		return false
	var definition := PotionCatalog.find(potion_id)
	if definition == null:
		return false
	if not inventory.consume(potion_id):
		return false
	PotionEffectResolver.apply(definition, caster)
	_cooldown_remaining = COOLDOWN_SECONDS
	slot_used.emit(n)
	return true

func serialize() -> Dictionary:
	return {"slots": _slots.duplicate()}

# Restores slot assignments from a previously-serialized dict (PRD #358 / slice 6).
# Cooldown state is intentionally NOT round-tripped — see commit notes on slice 4.
# An id that no longer exists in PotionCatalog is dropped silently so a save
# written against an old catalog version doesn't pin a slot to an inert string
# the use_slot guard would just reject every press anyway.
func deserialize(dict: Dictionary) -> void:
	_slots = ["", "", ""]
	_cooldown_remaining = 0.0
	if typeof(dict) != TYPE_DICTIONARY:
		return
	var slots = dict.get("slots", [])
	if typeof(slots) != TYPE_ARRAY:
		return
	for i in range(mini(slots.size(), SLOT_COUNT)):
		var pid := String(slots[i])
		if pid == "":
			continue
		if PotionCatalog.find(pid) == null:
			continue
		_slots[i] = pid

func _index_of(potion_id: String) -> int:
	for i in range(SLOT_COUNT):
		if _slots[i] == potion_id:
			return i
	return -1
