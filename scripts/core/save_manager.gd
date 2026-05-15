class_name SaveManager
extends RefCounted

const DEFAULT_PATH := "user://save.json"

static func save(c: CharacterData, path: String = DEFAULT_PATH, tree: SkillTree = null, tracker: MetaProgressionTracker = null, xp_tracker: OfflineXPTracker = null, cosmetic_inv: CosmeticInventory = null, paid_unlocks: PaidUnlockInventory = null, dungeon_run_state: Dictionary = {}, currency_ledger: CurrencyLedger = null, skill_inv = null, item_inventory: ItemInventory = null) -> Error:
	if c == null:
		return ERR_INVALID_PARAMETER
	var save_data := KittenSaveData.from_character(c, tree, tracker, xp_tracker, cosmetic_inv, paid_unlocks, dungeon_run_state, currency_ledger, skill_inv, item_inventory)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(save_data.to_dict()))
	f.close()
	return OK

# Zero-param full save (issue #112 / PRD #111). Reads every save field directly
# from the GameState autoload and assembles the snapshot internally so call
# sites stop owning the 10-argument tuple. The dungeon run state is serialized
# from `gs.dungeon_run_controller` using its own `seed` field — when the
# controller is null (no run in flight, multiplayer-only path) we pass an empty
# dict, matching the legacy `{}` argument every existing caller threaded
# through. The existing parametric `save()` is retained for the character-
# creation entry point that intentionally writes a minimal snapshot.
static func save_from_state(path: String = DEFAULT_PATH) -> Error:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null or gs.current_character == null:
		return ERR_INVALID_PARAMETER
	var run_state: Dictionary = {}
	if gs.dungeon_run_controller != null:
		run_state = DungeonRunSerializer.serialize(gs.dungeon_run_controller, gs.dungeon_run_controller.seed)
	return save(
		gs.current_character, path,
		gs.skill_tree, gs.meta_tracker, gs.offline_xp_tracker,
		gs.cosmetic_inventory, gs.paid_unlocks, run_state,
		gs.currency_ledger, gs.skill_inventory, gs.item_inventory
	)

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
