class_name SaveManager
extends RefCounted

const DEFAULT_PATH := "user://save.json"

static func save(c: CharacterData, path: String = DEFAULT_PATH, tree: SkillTree = null, tracker: MetaProgressionTracker = null, xp_tracker: OfflineXPTracker = null, cosmetic_inv: CosmeticInventory = null, paid_unlocks: PaidUnlockInventory = null, dungeon_run_state: Dictionary = {}, currency_ledger: CurrencyLedger = null, skill_inv = null, item_inventory: ItemInventory = null, quickbar: Quickbar = null, streak_day: int = 0, last_login_date: String = "", consumable_inventory: ConsumableInventory = null, potion_belt: PotionBelt = null) -> Error:
	if c == null:
		return ERR_INVALID_PARAMETER
	var save_data := KittenSaveData.from_character(c, tree, tracker, xp_tracker, cosmetic_inv, paid_unlocks, dungeon_run_state, currency_ledger, skill_inv, item_inventory, quickbar, streak_day, last_login_date, consumable_inventory, potion_belt)
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
	# Slice 2 (PRD #250): writes a SaveBundle, not a flat KittenSaveData.
	# Load the existing bundle first so other archetype slots survive — only
	# the active slot + account fields are overwritten from live state.
	var bundle := load_bundle(path)
	bundle.account = AccountSaveData.from_state(
		gs.currency_ledger, gs.cosmetic_inventory, gs.paid_unlocks,
		gs.skill_inventory, gs.meta_tracker,
		gs.streak_day, gs.last_login_date
	)
	var run_state: Dictionary = {}
	if gs.dungeon_run_controller != null:
		run_state = DungeonRunSerializer.serialize(gs.dungeon_run_controller, gs.dungeon_run_controller.seed)
	var slot := CharacterSlotData.from_state(
		gs.current_character, gs.skill_tree, gs.item_inventory,
		gs.current_quickbar, run_state, gs.offline_xp_tracker,
		gs.consumable_inventory, gs.potion_belt
	)
	bundle.set_slot(gs.current_character.character_class, slot)
	bundle.active_slot = SaveBundle.slot_key_for_class(gs.current_character.character_class)
	return save_bundle(bundle, path)

# Bundle persistence (PRD #250 / Slice 1). Writes a SaveBundle as a single
# combined JSON document. The bundle owns its own version + slot layout, so we
# just round-trip its dict here.
static func save_bundle(bundle: SaveBundle, path: String = DEFAULT_PATH) -> Error:
	if bundle == null:
		return ERR_INVALID_PARAMETER
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(bundle.to_dict()))
	f.close()
	return OK

# Always returns a SaveBundle (never null). Missing file, parse failure, or a
# legacy pre-rework flat save all yield a fresh empty bundle so the new save
# structure starts clean (PRD #250 "reset on upgrade").
static func load_bundle(path: String = DEFAULT_PATH) -> SaveBundle:
	if not FileAccess.file_exists(path):
		return SaveBundle.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return SaveBundle.new()
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return SaveBundle.new()
	return SaveBundle.from_dict(parsed)

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
	# Bundle detection (PRD #250 / slice 2): files written via save_from_state
	# are SaveBundles. Synthesize a flat KittenSaveData so existing callers
	# (Nakama sync, character_creation, every legacy test) keep working off
	# the same shape they used pre-rework.
	if parsed.has("version") and parsed.has("slots"):
		return KittenSaveData.from_bundle(SaveBundle.from_dict(parsed))
	return KittenSaveData.from_dict(parsed)
