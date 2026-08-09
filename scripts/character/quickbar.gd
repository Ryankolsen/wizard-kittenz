class_name Quickbar
extends RefCounted

# Pure-data 4-slot spell quickbar. No Godot scene or HUD references — owned
# per-character and unit-testable in isolation. Slots are 1-indexed (1..SLOT_COUNT)
# to match player-facing InputMap actions cast_slot_1..cast_slot_4.

const SLOT_COUNT := 4

signal slot_changed(slot: int)
signal slot_fired(slot: int)
signal channel_started(slot: int)
signal channel_completed(slot: int)
signal channel_cancelled(slot: int)

var _slots: Array = [null, null, null, null]

# Cast-channel state (issue #476). At most one channel is active at a time —
# fire_slot() on a cast_time > 0 spell starts it instead of casting
# immediately; tick()/on_damage_taken() (driven by Player each physics frame
# and on damage respectively) advance or cancel it. The underlying
# Spell.cast() — and therefore its cooldown/MP/HP cost — only runs once the
# channel completes uninterrupted, so a cancelled channel never consumes a
# cooldown and can be retried right away.
var _channel := CastChannel.new()
var _channel_slot: int = -1
var _channel_caster = null

# Real-world hourly cooldown for Summon Gwendolyn specifically (issue #477),
# layered on top of (not replacing) the cast-channel above. Unix timestamp
# of the last successful, uninterrupted cast; 0 = never cast. Persisted via
# CharacterSlotData.gwendolyn_last_summon_unix so it survives app restarts.
const _GWENDOLYN_SPELL_ID := "summon_gwendolyn"
var gwendolyn_last_summon_unix: int = 0

static func _resolve_now(now_unix: int) -> int:
	return now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())

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

# Attempts to fire the spell in slot n. Instant spells (cast_time == 0, the
# default and every spell predating issue #476) call spell.cast(caster)
# immediately as before. Channeled spells (cast_time > 0) start a cast-channel
# instead — spell.cast() is deferred until tick() reports the channel
# complete, so cooldown/MP/HP are untouched unless the channel finishes
# uninterrupted. Returns false (no state mutation) for an empty slot, an
# on-cooldown spell, or while another channel is already active.
# Emits slot_fired(n) only on successful instant cast or completed channel.
# now_unix is an optional real-world-clock override for the Gwendolyn
# hourly-cooldown check below (issue #477); -1 (default) reads the system
# clock, tests pass a fixed value for deterministic assertions.
func fire_slot(n: int, caster = null, now_unix: int = -1) -> bool:
	if n < 1 or n > SLOT_COUNT:
		return false
	if is_channeling():
		return false
	var spell: Spell = _slots[n - 1]
	if spell == null:
		return false
	if spell.id == _GWENDOLYN_SPELL_ID and not GwendolynCooldown.is_ready(gwendolyn_last_summon_unix, _resolve_now(now_unix)):
		return false
	if spell.cast_time > 0.0:
		if not spell.is_ready():
			return false
		_channel.start(spell.cast_time)
		_channel_slot = n
		_channel_caster = caster
		channel_started.emit(n)
		return true
	if not spell.cast(caster):
		return false
	if spell.id == _GWENDOLYN_SPELL_ID:
		gwendolyn_last_summon_unix = _resolve_now(now_unix)
	slot_fired.emit(n)
	return true

func is_channeling() -> bool:
	return _channel.is_active()

# Advances the active channel by dt. Called once per physics frame by the
# player/quickbar wiring (mirrors Spell.tick's per-spell cooldown decay). A
# completed channel fires the deferred spell.cast() now — cooldown/MP/HP are
# consumed here, not at start(), so an interrupted channel never pays those
# costs.
func tick(dt: float, now_unix: int = -1) -> void:
	if not _channel.is_active():
		return
	_channel.tick(dt)
	if not _channel.is_complete():
		return
	var n := _channel_slot
	var caster = _channel_caster
	_channel_slot = -1
	_channel_caster = null
	var spell: Spell = _slots[n - 1] if n >= 1 and n <= SLOT_COUNT else null
	if spell != null and spell.cast(caster):
		if spell.id == _GWENDOLYN_SPELL_ID:
			gwendolyn_last_summon_unix = _resolve_now(now_unix)
		slot_fired.emit(n)
	channel_completed.emit(n)

# Cancels the active channel (safe no-op if none is active). No cooldown is
# consumed and the slot can be fired again immediately.
func on_damage_taken() -> void:
	if not _channel.is_active():
		return
	_channel.on_damage_taken()
	var n := _channel_slot
	_channel_slot = -1
	_channel_caster = null
	channel_cancelled.emit(n)

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
