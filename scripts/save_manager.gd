class_name SaveManager
extends RefCounted

const DEFAULT_PATH := "user://save.json"

static func save(c: CharacterData, path: String = DEFAULT_PATH, tree: SkillTree = null, tracker: MetaProgressionTracker = null, xp_tracker: OfflineXPTracker = null, cosmetic_inv: CosmeticInventory = null, paid_unlocks: PaidUnlockInventory = null, dungeon_run_state: Dictionary = {}, currency_ledger: CurrencyLedger = null) -> Error:
	if c == null:
		return ERR_INVALID_PARAMETER
	var save_data := KittenSaveData.from_character(c, tree, tracker, xp_tracker, cosmetic_inv, paid_unlocks, dungeon_run_state, currency_ledger)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(save_data.to_dict()))
	f.close()
	return OK

# Note: shadows the global `load()` for `SaveManager.load()` calls — that's the
# name the issue specifies. Global `load()` is still reachable from elsewhere.
static func load(path: String = DEFAULT_PATH) -> KittenSaveData:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return null
	return KittenSaveData.from_dict(parsed)
