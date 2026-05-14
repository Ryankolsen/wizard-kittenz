extends Node

# Sibling class_name resolution is load-order-fragile (see prior commits);
# preload the serializer so the autoload script parses regardless of
# script-load order.
const DungeonRunSerializerRef = preload("res://scripts/dungeon_run_serializer.gd")
const SkillInventoryRef = preload("res://scripts/skill_inventory.gd")
const ItemStatApplicatorRef = preload("res://scripts/item_stat_applicator.gd")

signal save_synced(merged: KittenSaveData)

var current_character: CharacterData = null
var skill_tree: SkillTree = null
# Lifetime stats used by UnlockRegistry to evaluate gates. Always non-null
# after _ready so call sites can read freely; a fresh tracker (everything
# zero) is the right default for a brand-new save.
var meta_tracker: MetaProgressionTracker = MetaProgressionTracker.new()
var unlock_registry: UnlockRegistry = UnlockRegistry.make_default()
# XP earned in the solo path since the last server sync. Always non-null
# so the kill flow / save layer can read .pending_xp freely without a
# null check. Hydrated from KittenSaveData.offline_xp_earned on load;
# the sync orchestrator (post-#14) calls clear() after a successful
# OfflineProgressMerger.merge_xp.
var offline_xp_tracker: OfflineXPTracker = OfflineXPTracker.new()
# Owned cosmetic packs (non-consumable IAPs from #29). Always non-null so the
# shop UI (#33) and grant handler (#32) can read freely without a null check;
# hydrated from KittenSaveData.cosmetic_packs in apply_merged_save.
var cosmetic_inventory: CosmeticInventory = CosmeticInventory.new()
# Paid class-unlock entries (non-consumable IAPs, PRD #26 Tier 3). Always
# non-null so UnlockRegistry.is_unlocked and the grant handler can read freely
# without a null check; hydrated from KittenSaveData.paid_class_unlocks in
# apply_merged_save.
var paid_unlocks: PaidUnlockInventory = PaidUnlockInventory.new()
# Dual-currency balances (PRD #53). Always non-null so the kill flow, room
# clear watcher, and shop UI can credit/debit without a null check.
# Hydrated from KittenSaveData.to_currency_ledger() in apply_merged_save.
var currency_ledger: CurrencyLedger = CurrencyLedger.new()
# Owned skill ids (PRD #53 / issue #69). Always non-null so the grant handler
# and future SkillTree availability gate can read freely without a null
# check. Hydrated from KittenSaveData.to_skill_inventory() in apply_merged_save.
var skill_inventory = SkillInventoryRef.new()
# Equipped items + bag (PRD #73 / issue #81). Always non-null so the loot
# prompt (#80) and pause-menu equipment panel (#82) can read freely without
# a null check. Hydrated from KittenSaveData.to_item_inventory() in
# apply_merged_save; reset to a fresh inventory in clear().
var item_inventory: ItemInventory = ItemInventory.new()
# Active co-op session. Non-null only between the lobby's Start Match
# handler and session end (player back-out / dungeon failed). Player.gd's
# kill flow null-checks this to branch between solo (apply XP locally)
# and co-op (broadcast XP via session.xp_broadcaster). Sourced from the
# lobby UI once #16 lands; default null preserves the solo behavior on
# fresh-install / no-multiplayer paths.
var coop_session: CoopSession = null
# Active pre-game lobby. Non-null between "Create/Join Room" and match start
# (or leave). The lobby scene reads this to bind signals; the character
# creation scene writes it after a successful create_async / join_async.
var lobby: NakamaLobby = null
# This client's player_id within an active co-op session. Sourced from
# AccountManager once Google Play Games auth (#15 follow-up) lands;
# default empty string keeps the solo branch firing until co-op is
# wired. Stored on GameState (not just CoopSession) so it survives
# across sessions (multiple matches in a row, lobby reconstruction)
# and so a single source of truth reads from AccountManager.
var local_player_id: String = ""
var account_manager: AccountManager = AccountManager.new()
# Active dungeon run controller. Non-null between dungeon start and completion
# (boss cleared or player gives up). Stored on GameState so it survives
# scene reloads when the player advances between rooms. Cleared on dungeon
# completion or give-up so a fresh run gets a new dungeon.
var dungeon_run_controller: DungeonRunController = null

func _ready() -> void:
	_try_load_save()
	NakamaService.authenticated.connect(_on_nakama_authenticated)
	# BillingManager is declared after GameState in project.godot, so its
	# autoload node isn't on the tree yet when our _ready runs. Defer the
	# connect to the next idle tick when all autoloads exist.
	_connect_billing_signal.call_deferred()

func _connect_billing_signal() -> void:
	var bm := get_node_or_null("/root/BillingManager")
	if bm == null:
		return
	if not bm.purchase_succeeded.is_connected(_on_purchase_succeeded):
		bm.purchase_succeeded.connect(_on_purchase_succeeded)

func _on_purchase_succeeded(product_id: String) -> void:
	# Only persist when the handler actually applied a grant. Restore-from-
	# server replays for already-owned cosmetics return false here, so a
	# user opening the app twenty times doesn't rewrite the save file twenty
	# times for no reason.
	if PurchaseGrantHandler.handle(product_id, current_character, cosmetic_inventory, paid_unlocks, currency_ledger, skill_inventory):
		SaveManager.save(
			current_character, SaveManager.DEFAULT_PATH,
			skill_tree, meta_tracker, offline_xp_tracker, cosmetic_inventory, paid_unlocks,
			{}, currency_ledger, skill_inventory, item_inventory
		)

func _try_load_save() -> void:
	var save_data := SaveManager.load()
	if save_data != null:
		apply_merged_save(save_data)

func apply_merged_save(save_data: KittenSaveData) -> void:
	var c := CharacterData.new()
	save_data.apply_to(c)
	current_character = c
	skill_tree = _build_tree_for(c)
	skill_tree.apply_unlocked_ids(save_data.unlocked_skill_ids)
	meta_tracker = save_data.to_tracker()
	offline_xp_tracker = save_data.to_offline_xp_tracker()
	cosmetic_inventory = save_data.to_cosmetic_inventory()
	paid_unlocks = save_data.to_paid_unlock_inventory()
	currency_ledger = save_data.to_currency_ledger()
	skill_inventory = save_data.to_skill_inventory()
	item_inventory = save_data.to_item_inventory()
	ItemStatApplicatorRef.apply(item_inventory, current_character)
	# Resume an in-flight solo dungeon run (PRD #42 / #46). When the saved
	# state is empty (legacy save / no run in flight / multiplayer-only) the
	# serializer returns null and main_scene falls through to
	# _start_new_dungeon. The serializer regenerates the dungeon from the
	# stored seed, advances the controller to the saved room, and replays
	# explicit clears.
	dungeon_run_controller = DungeonRunSerializerRef.deserialize(save_data.dungeon_run_state)

func _on_nakama_authenticated(p_session: NakamaSession) -> void:
	account_manager.sign_in(p_session.user_id)
	local_player_id = p_session.user_id
	var local := SaveManager.load()
	var server_dict: Dictionary = await NakamaService.fetch_save_async(p_session)
	var server: KittenSaveData = null
	if not server_dict.is_empty():
		server = KittenSaveData.from_dict(server_dict)
	var merged := SaveSyncOrchestrator.sync(local, server, offline_xp_tracker)
	if merged == null:
		return
	# Zero the pending-XP field before hydrating and uploading — the delta is
	# already baked into merged.xp (via merge_xp or the local-wins clone), so
	# the "since last sync" window resets to zero on both stores.
	merged.offline_xp_earned = 0
	apply_merged_save(merged)
	SaveManager.save(
		current_character, SaveManager.DEFAULT_PATH,
		skill_tree, meta_tracker, offline_xp_tracker, cosmetic_inventory, paid_unlocks,
		{}, currency_ledger, skill_inventory, item_inventory
	)
	await NakamaService.upload_save_async(p_session, merged.to_dict())
	save_synced.emit(merged)

func set_character(c: CharacterData) -> void:
	current_character = c
	skill_tree = _build_tree_for(c)

func clear() -> void:
	current_character = null
	skill_tree = null
	meta_tracker = MetaProgressionTracker.new()
	offline_xp_tracker = OfflineXPTracker.new()
	cosmetic_inventory = CosmeticInventory.new()
	paid_unlocks = PaidUnlockInventory.new()
	currency_ledger = CurrencyLedger.new()
	skill_inventory = SkillInventoryRef.new()
	item_inventory = ItemInventory.new()
	# Tear down any live co-op session before dropping the reference so
	# the per-run managers unbind cleanly and don't keep handing XP to
	# a member.real_stats that's about to be replaced.
	if coop_session != null and coop_session.is_active():
		coop_session.end()
	coop_session = null
	local_player_id = ""
	if lobby != null:
		_disconnect_lobby_signals(lobby)
	lobby = null
	dungeon_run_controller = null

# Lobby setter — routes the inbound position_received signal into
# coop_session.network_sync. The character creation / lobby UI scene calls
# this after a successful create/join so the Player's outbound broadcast
# (via Player._maybe_broadcast_position -> lobby.send_position_async) and
# the inbound interpolation (via this handler -> network_sync.apply_remote_state)
# share a single source-of-truth NakamaLobby reference.
func set_lobby(new_lobby: NakamaLobby) -> void:
	if lobby != null:
		_disconnect_lobby_signals(lobby)
	lobby = new_lobby
	if lobby != null:
		lobby.position_received.connect(_on_position_received)
		lobby.kill_received.connect(_on_kill_received)
		lobby.host_paused.connect(_on_host_paused)
		lobby.host_unpaused.connect(_on_host_unpaused)

func _disconnect_lobby_signals(old: NakamaLobby) -> void:
	if old.position_received.is_connected(_on_position_received):
		old.position_received.disconnect(_on_position_received)
	if old.kill_received.is_connected(_on_kill_received):
		old.kill_received.disconnect(_on_kill_received)
	if old.host_paused.is_connected(_on_host_paused):
		old.host_paused.disconnect(_on_host_paused)
	if old.host_unpaused.is_connected(_on_host_unpaused):
		old.host_unpaused.disconnect(_on_host_unpaused)

# Host-pause scene-tree bridge (#43). NakamaLobby's wire layer flips
# host_pause_state and emits host_paused / host_unpaused on a real edge;
# this binds those edges to get_tree().paused so every client freezes in
# lockstep with the host's pause press. Distinct from PauseMenu.open()'s
# solo-only tree pause (#44) — that one is per-player; this one is party-
# wide and gated on host authority by the lobby.
func _on_host_paused() -> void:
	get_tree().paused = true

func _on_host_unpaused() -> void:
	get_tree().paused = false

func _on_position_received(player_id: String, position: Vector2, timestamp: float) -> void:
	if coop_session == null or coop_session.network_sync == null:
		return
	coop_session.network_sync.apply_remote_state(player_id, position, timestamp)

# Inbound kill bridge — wire packet → RemoteKillApplier (data side) +
# RemoteEnemyDespawner (scene side). apply_death's idempotent gate rejects
# duplicate packets; xp_broadcaster fans XP to every party member's
# LocalXPRouter (the local player picks its own emission and applies to
# member.real_stats). Solo path / pre-session (coop_session == null) is a
# silent no-op via RemoteKillApplier's own null-check.
#
# Despawn is gated on RemoteKillApplier's rising-edge true return so a
# duplicate packet doesn't re-scan the scene tree for an already-freed
# node. AC#4 ("no ghost enemies") closes here: the visible Enemy
# CharacterBody2D disappears in lockstep with the registry update.
func _on_kill_received(enemy_id: String, killer_id: String, xp_value: int) -> void:
	if not RemoteKillApplier.apply(coop_session, enemy_id, killer_id, xp_value):
		return
	RemoteEnemyDespawner.despawn(get_tree(), enemy_id)

# Per-class tree builder. Each class gets its own factory so unlocks on one
# class's tree never bleed into another's (independent-trees acceptance
# criterion from #10). Unknown class falls through to the mage tree as a safe
# default — better than returning null and forcing every call site to
# null-check.
func _build_tree_for(c: CharacterData) -> SkillTree:
	match c.character_class:
		CharacterData.CharacterClass.MAGE: return SkillTree.make_mage_tree()
		CharacterData.CharacterClass.THIEF: return SkillTree.make_thief_tree()
		CharacterData.CharacterClass.NINJA: return SkillTree.make_ninja_tree()
		CharacterData.CharacterClass.ARCHMAGE: return SkillTree.make_mage_tree()
		CharacterData.CharacterClass.MASTER_THIEF: return SkillTree.make_thief_tree()
		CharacterData.CharacterClass.SHADOW_NINJA: return SkillTree.make_ninja_tree()
	return SkillTree.make_mage_tree()
