class_name PaidUnlockInventory
extends RefCounted

# Tracks which classes the local player has unlocked via a non-consumable IAP
# (PRD #26 Tier 3 — "Class Unlock Shortcut"). Sibling to CosmeticInventory:
# permanent one-time grant, so the only state per id is "owned or not."
#
# Stored alongside KittenSaveData.paid_class_unlocks; the save layer round-trips
# the array verbatim. UnlockRegistry.is_unlocked consults this inventory as an
# OR'd path next to the gameplay condition gates — a paid unlock bypasses the
# meta-progression threshold without removing the earnable path (PRD's
# "earnable through gameplay OR purchased").

var owned_class_ids: Array = []

func grant(class_id: String) -> bool:
	var key := class_id.to_lower()
	if key == "":
		return false
	if owned_class_ids.has(key):
		return false
	owned_class_ids.append(key)
	return true

func has_unlock(class_id: String) -> bool:
	return owned_class_ids.has(class_id.to_lower())

func to_dict() -> Dictionary:
	return {"owned_class_ids": owned_class_ids.duplicate()}

static func from_dict(d: Dictionary) -> PaidUnlockInventory:
	var inv := PaidUnlockInventory.new()
	var ids = d.get("owned_class_ids", [])
	if ids is Array:
		for raw in ids:
			var key := String(raw).to_lower()
			if key != "" and not inv.owned_class_ids.has(key):
				inv.owned_class_ids.append(key)
	return inv
