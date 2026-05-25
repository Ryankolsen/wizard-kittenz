class_name SaveBundle
extends RefCounted

# Top-level persisted structure for the multi-save rework (PRD #250).
# Holds one AccountSaveData plus a map of archetype-slot-key →
# CharacterSlotData, with an active_slot marker. Serializes to/from a single
# JSON dict so SaveManager can write the whole game's state as one document.
#
# Slot keys are archetype strings (battle/wizard/sleepy/chonk). A Kitten and
# its Cat upgrade share a slot key, so an in-place evolution (PRD story 24)
# carries the same CharacterSlotData through the class change without a
# slot migration.
#
# Legacy detection: a file without `version` or `slots` is treated as the
# pre-rework flat save format and discarded — from_dict returns an empty
# bundle rather than crashing (PRD story 28, "reset on upgrade").

const VERSION := 1

const SLOT_BATTLE := "battle"
const SLOT_WIZARD := "wizard"
const SLOT_SLEEPY := "sleepy"
const SLOT_CHONK := "chonk"

var version: int = VERSION
var account: AccountSaveData = AccountSaveData.new()
# String slot-key → CharacterSlotData
var slots: Dictionary = {}
var active_slot: String = ""

static func slot_key_for_class(klass: int) -> String:
	match klass:
		CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT:
			return SLOT_BATTLE
		CharacterData.CharacterClass.WIZARD_KITTEN, CharacterData.CharacterClass.WIZARD_CAT:
			return SLOT_WIZARD
		CharacterData.CharacterClass.SLEEPY_KITTEN, CharacterData.CharacterClass.SLEEPY_CAT:
			return SLOT_SLEEPY
		CharacterData.CharacterClass.CHONK_KITTEN, CharacterData.CharacterClass.CHONK_CAT:
			return SLOT_CHONK
	return ""

func set_slot(klass: int, slot: CharacterSlotData) -> void:
	var key := slot_key_for_class(klass)
	if key == "":
		return
	slots[key] = slot

func get_slot(klass_or_key) -> CharacterSlotData:
	var key: String
	if klass_or_key is String:
		key = klass_or_key
	else:
		key = slot_key_for_class(int(klass_or_key))
	return slots.get(key, null)

func occupied_slot_keys() -> Array:
	return slots.keys()

func to_dict() -> Dictionary:
	var slot_dict := {}
	for key in slots.keys():
		var s: CharacterSlotData = slots[key]
		if s != null:
			slot_dict[key] = s.to_dict()
	return {
		"version": version,
		"account": account.to_dict(),
		"slots": slot_dict,
		"active_slot": active_slot,
	}

static func from_dict(d: Dictionary) -> SaveBundle:
	var b := SaveBundle.new()
	# Legacy / unknown format detection: a real bundle has both `version` and
	# `slots`. A pre-rework flat save (top-level character_name/level/etc.) has
	# neither, so we discard it and yield a fresh empty bundle. An empty dict
	# also lands here.
	if not d.has("version") or not d.has("slots"):
		return b
	b.version = int(d.get("version", VERSION))
	var account_dict = d.get("account", {})
	if account_dict is Dictionary:
		b.account = AccountSaveData.from_dict(account_dict)
	var slot_dict = d.get("slots", {})
	if slot_dict is Dictionary:
		for key in slot_dict.keys():
			var raw = slot_dict[key]
			if raw is Dictionary:
				b.slots[String(key)] = CharacterSlotData.from_dict(raw)
	b.active_slot = String(d.get("active_slot", ""))
	return b
