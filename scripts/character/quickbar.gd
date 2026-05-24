class_name Quickbar
extends RefCounted

# Pure-data 4-slot spell quickbar. No Godot scene or HUD references — owned
# per-character and unit-testable in isolation. Slots are 1-indexed (1..SLOT_COUNT)
# to match player-facing InputMap actions cast_slot_1..cast_slot_4.

const SLOT_COUNT := 4

signal slot_changed(slot: int)
signal slot_fired(slot: int)

var _slots: Array = [null, null, null, null]

func get_slot(n: int) -> Spell:
	if n < 1 or n > SLOT_COUNT:
		return null
	return _slots[n - 1]

# Assigns spell into slot n with single-occupancy invariant. If the spell already
# occupies another slot, the two slots swap their contents (the previous occupant
# of n moves to where the spell was). Assigning the same slot's current occupant
# is a no-op.
func assign(n: int, spell: Spell) -> void:
	if n < 1 or n > SLOT_COUNT or spell == null:
		return
	var target_idx := n - 1
	if _slots[target_idx] == spell:
		return
	var existing_idx := _index_of(spell)
	if existing_idx == target_idx:
		return
	if existing_idx != -1:
		var prev = _slots[target_idx]
		_slots[target_idx] = spell
		_slots[existing_idx] = prev
		slot_changed.emit(existing_idx + 1)
		slot_changed.emit(n)
		return
	_slots[target_idx] = spell
	slot_changed.emit(n)

func unassign(n: int) -> void:
	if n < 1 or n > SLOT_COUNT:
		return
	if _slots[n - 1] == null:
		return
	_slots[n - 1] = null
	slot_changed.emit(n)

# Auto-fills the lowest-numbered empty slot with spell. No-op if the spell is
# already assigned anywhere, or if all slots are full.
func on_spell_unlocked(spell: Spell) -> void:
	if spell == null:
		return
	if _index_of(spell) != -1:
		return
	for i in range(SLOT_COUNT):
		if _slots[i] == null:
			_slots[i] = spell
			slot_changed.emit(i + 1)
			return

# Attempts to fire the spell in slot n by calling spell.cast(caster). Returns
# the cast outcome (false if slot empty, on cooldown, insufficient MP/HP, etc.).
# Emits slot_fired(n) only on successful cast.
func fire_slot(n: int, caster = null) -> bool:
	if n < 1 or n > SLOT_COUNT:
		return false
	var spell: Spell = _slots[n - 1]
	if spell == null:
		return false
	if not spell.cast(caster):
		return false
	slot_fired.emit(n)
	return true

# Returns {"slots": ["spell_id_or_empty", ...]} suitable for JSON round-trip.
# Empty slots serialize as "" so the list keeps positional meaning.
func serialize() -> Dictionary:
	var ids: Array = []
	for s in _slots:
		ids.append(s.id if s != null else "")
	return {"slots": ids}

# Restores slot assignments from a dict produced by serialize(). Spell ids are
# looked up in the supplied SkillTree (Quickbar holds no spell catalog of its
# own). Unknown ids and empty strings leave the slot empty. Tolerates short or
# missing arrays — any unset slot stays null.
func deserialize(dict: Dictionary, tree: SkillTree) -> void:
	_slots = [null, null, null, null]
	if tree == null:
		return
	var ids = dict.get("slots", [])
	if typeof(ids) != TYPE_ARRAY:
		return
	for i in range(min(ids.size(), SLOT_COUNT)):
		var sid := str(ids[i])
		if sid == "":
			continue
		var node := tree.find(sid)
		if node != null and node.spell != null:
			_slots[i] = node.spell

func _index_of(spell: Spell) -> int:
	for i in range(SLOT_COUNT):
		if _slots[i] == spell:
			return i
	return -1
