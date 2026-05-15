class_name SkillInventory
extends RefCounted

# Tracks which skills the local player has unlocked via a non-consumable
# purchase (PRD #53 / issue #69). Sibling to PaidUnlockInventory:
# permanent one-time grant, so the only state per id is "owned or not."
#
# Stored alongside KittenSaveData.skill_unlocks; the save layer round-trips
# the array verbatim. The eventual SkillTree / skill activation layer
# (post-#71) will consult has_skill to gate availability without removing
# the earnable path — same OR'd-gate shape PaidUnlockInventory takes
# alongside UnlockRegistry condition gates.

var owned_skill_ids: Array = []

func grant(skill_id: String) -> bool:
	var key := skill_id.to_lower()
	if key == "":
		return false
	if owned_skill_ids.has(key):
		return false
	owned_skill_ids.append(key)
	return true

func has_skill(skill_id: String) -> bool:
	return owned_skill_ids.has(skill_id.to_lower())

func to_dict() -> Dictionary:
	return {"owned_skill_ids": owned_skill_ids.duplicate()}

static func from_dict(d: Dictionary):
	# Use runtime load() not the class_name. game_state.gd preloads this file
	# at parse time, and during that initial parse our own class_name is not
	# yet in the global registry — so `SkillInventory.new()` here would fail
	# to compile. load() resolves at runtime, by which point the registry is
	# fully populated (and returns the same already-loaded script).
	var script = load("res://scripts/progression/skill_inventory.gd")
	var inv = script.new()
	var ids = d.get("owned_skill_ids", [])
	if ids is Array:
		for raw in ids:
			var key := String(raw).to_lower()
			if key != "" and not inv.owned_skill_ids.has(key):
				inv.owned_skill_ids.append(key)
	return inv
