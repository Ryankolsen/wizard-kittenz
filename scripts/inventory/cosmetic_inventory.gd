class_name CosmeticInventory
extends RefCounted

# Tracks which non-consumable cosmetic packs the local player owns. Mirrors the
# shape of the old TokenInventory (thin RefCounted, JSON-round-trippable) but
# stores a *set* of pack ids rather than a count — cosmetic IAPs are permanent
# one-time grants, so the only state per pack is "owned or not."
#
# Persisted via KittenSaveData.cosmetic_packs; the save layer round-trips the
# array verbatim. The shop UI (#33) reads has_pack; the grant handler (#32)
# calls grant on a purchase_succeeded event.

var owned_pack_ids: Array = []

func grant(pack_id: String) -> bool:
	if owned_pack_ids.has(pack_id):
		return false
	owned_pack_ids.append(pack_id)
	return true

func has_pack(pack_id: String) -> bool:
	return owned_pack_ids.has(pack_id)

func to_dict() -> Dictionary:
	return {"owned_pack_ids": owned_pack_ids.duplicate()}

static func from_dict(d: Dictionary) -> CosmeticInventory:
	var inv := CosmeticInventory.new()
	var ids = d.get("owned_pack_ids", [])
	if ids is Array:
		inv.owned_pack_ids = ids.duplicate()
	return inv
