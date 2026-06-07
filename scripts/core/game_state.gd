extends Node

# Sibling class_name resolution is load-order-fragile (see prior commits);
# preload the serializer so the autoload script parses regardless of
# script-load order.
const DungeonRunSerializerRef = preload("res://scripts/dungeon/dungeon_run_serializer.gd")
const SkillInventoryRef = preload("res://scripts/progression/skill_inventory.gd")
const SkillUnlockCheckerRef = preload("res://scripts/progression/skill_unlock_checker.gd")
const _RemoteHealApplierRef = preload("res://scripts/networking/remote_heal_applier.gd")
const _RemoteItemDropResolverRef = preload("res://scripts/networking/remote_item_drop_resolver.gd")
const _RemoteDamageVisualizerRef = preload("res://scripts/networking/remote_damage_visualizer.gd")
const _RemoteEnemyDamageApplierRef = preload("res://scripts/networking/remote_enemy_damage_applier.gd")

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
# Per-character potion stack counts (PRD #358 / slice 5). Always non-null so the
# shop grant handler and the future PotionBeltHUD can read freely without a null
# check. Slice 6 (#364) wires serialize/deserialize into the save bundle; for
# now the field resets on session start, which is fine — slice 5's acceptance
# criterion is just that purchases land in the in-memory inventory.
var consumable_inventory: ConsumableInventory = ConsumableInventory.new()
# Per-character potion belt (PRD #358 / slice 4+6). Always non-null so the
# PotionBeltHUD (slice 8) + input action bindings can read freely without a
# null check. Slot assignments persist via the save bundle; the shared
# cooldown intentionally does not survive a session (see slice 4 commit).
var potion_belt: PotionBelt = PotionBelt.new()
# Per-character spell quickbar (PRD #210 / slice 5). Built once per
# character — either deserialized from the save via to_quickbar() (live
# bindings restored) or freshly auto-filled from the tree's unlocked
# spells (legacy save migration + brand-new characters). Player reads
# this in _init_quickbar instead of bootstrapping from the tree itself
# so manual assignments survive across saves.
var current_quickbar: Quickbar = null
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
# Daily-login streak bookkeeping (PRD #237). Live mirror of the save fields
# so the engine (#241) can read/write them through GameState and
# save_from_state can persist them without an extra round-trip. Hydrated
# from KittenSaveData in apply_merged_save; reset in clear().
var streak_day: int = 0
var last_login_date: String = ""

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
	if PurchaseGrantHandler.handle(product_id, current_character, cosmetic_inventory, paid_unlocks, currency_ledger, skill_inventory, item_inventory, consumable_inventory):
		SaveManager.save_from_state()

func _try_load_save() -> void:
	# Slice 2 (PRD #250): the on-disk save is a SaveBundle. Account-wide
	# fields hydrate every load (even with no active character — lands on
	# menu with gold/cosmetics/etc. intact). The active slot's character
	# hydrates only when one exists.
	hydrate_from_bundle(SaveManager.load_bundle())

func hydrate_from_bundle(bundle: SaveBundle) -> void:
	if bundle == null:
		return
	_hydrate_account(bundle.account)
	var slot: CharacterSlotData = bundle.get_slot(bundle.active_slot) if bundle.active_slot != "" else null
	if slot != null:
		_hydrate_active_character(slot)

func _hydrate_account(account: AccountSaveData) -> void:
	if account == null:
		return
	cosmetic_inventory = CosmeticInventory.new()
	cosmetic_inventory.owned_pack_ids = account.cosmetic_packs.duplicate()
	paid_unlocks = PaidUnlockInventory.new()
	paid_unlocks.owned_class_ids = account.paid_class_unlocks.duplicate()
	currency_ledger = CurrencyLedger.new()
	if account.gold_balance > 0:
		currency_ledger.credit(account.gold_balance, CurrencyLedger.Currency.GOLD)
	if account.gem_balance > 0:
		currency_ledger.credit(account.gem_balance, CurrencyLedger.Currency.GEM)
	skill_inventory = SkillInventoryRef.new()
	skill_inventory.owned_skill_ids = account.skill_unlocks.duplicate()
	meta_tracker = MetaProgressionTracker.new()
	meta_tracker.dungeons_completed = account.dungeons_completed
	meta_tracker.max_level_per_class = account.max_level_per_class.duplicate()
	for id in account.cleared_dungeons:
		var s_id := String(id)
		if s_id != "" and not meta_tracker.cleared_dungeons.has(s_id):
			meta_tracker.cleared_dungeons.append(s_id)
	streak_day = account.streak_day
	last_login_date = account.last_login_date

func _hydrate_active_character(slot: CharacterSlotData) -> void:
	var c := CharacterData.new()
	c.character_name = slot.character_name
	c.character_class = slot.character_class
	c.appearance_index = slot.appearance_index
	c.level = slot.level
	c.xp = slot.xp
	c.hp = slot.hp
	c.max_hp = slot.max_hp
	c.attack = slot.attack
	c.defense = slot.defense
	c.speed = slot.speed
	c.skill_points = slot.skill_points
	c.magic_attack = slot.magic_attack
	c.magic_points = slot.magic_points
	c.max_mp = slot.max_mp
	c.magic_resistance = slot.magic_resistance
	c.dexterity = slot.dexterity
	c.evasion = slot.evasion
	c.crit_chance = slot.crit_chance
	c.luck = slot.luck
	c.regeneration = slot.regeneration
	c.mp_regen = slot.mp_regen
	c.allocated_points = slot.allocated_points.duplicate()
	c.schema_version = slot.schema_version
	# PRD #316 / issue #319: respec pre-tier saves before item bonuses are
	# (re)applied so the refund only touches allocation-derived stats. No-op
	# once the slot's schema_version is at SkillPointRespec.CURRENT_VERSION.
	SkillPointRespec.migrate(c)
	current_character = c
	skill_tree = _build_tree_for(c)
	skill_tree.apply_unlocked_ids(slot.unlocked_skill_ids)
	SkillUnlockCheckerRef.auto_unlock_for_level(skill_tree, current_character.level)
	offline_xp_tracker = OfflineXPTracker.new()
	offline_xp_tracker.pending_xp = slot.offline_xp_earned
	item_inventory = ItemInventory.new()
	for slot_key in slot.equipped_items.keys():
		var item := ItemCatalog.find(String(slot.equipped_items[slot_key]))
		if item != null:
			item_inventory.equip(item)
	for raw_id in slot.item_bag:
		var item2 := ItemCatalog.find(String(raw_id))
		if item2 != null:
			item_inventory.add_to_bag(item2)
	CharacterMutator.new(current_character).apply_item_bonuses(item_inventory)
	dungeon_run_controller = DungeonRunSerializerRef.deserialize(slot.dungeon_run_state)
	# Quickbar: build AFTER unlocks/level top-up so the legacy-save fallback
	# inside Quickbar walks the correct unlocked spell set. An empty
	# quickbar_slots array (saved before the field existed) auto-fills from
	# the tree; once any slot is bound the next save pins the layout.
	var qb := Quickbar.new()
	if slot.quickbar_slots.size() > 0:
		qb.deserialize({"slots": slot.quickbar_slots}, skill_tree)
	else:
		for spell in skill_tree.get_unlocked_spells():
			qb.on_spell_unlocked(spell)
	current_quickbar = qb
	# Potion persistence (PRD #358 / slice 6). Restore stack counts + belt slot
	# assignments from the slot. Unknown ids (catalog dropped a potion since
	# the save was written) are filtered defensively inside the helpers.
	consumable_inventory = ConsumableInventory.new()
	for k in slot.consumable_inventory_data.keys():
		var pid := String(k)
		if PotionCatalog.find(pid) == null:
			continue
		var amount := int(slot.consumable_inventory_data[k])
		if amount > 0:
			consumable_inventory.add(pid, amount)
	potion_belt = PotionBelt.new()
	potion_belt.deserialize({"slots": slot.potion_belt_slots})

# Multi-save slot switching (PRD #250 / slice 3). Persist the outgoing
# character into the bundle's current active slot first so its progress
# survives the swap, then re-hydrate only the per-character side from the
# target slot — account-wide live state (currency, unlocks, meta,
# cosmetics, skill inventory, streak) stays in place because we never
# re-run _hydrate_account here. If the target slot is empty this leaves
# current_character null (caller is expected to push to character creation).
func switch_to_slot(archetype: String) -> void:
	if current_character != null:
		SaveManager.save_from_state()
	var bundle := SaveManager.load_bundle()
	var target: CharacterSlotData = bundle.get_slot(archetype)
	if target == null:
		current_character = null
		skill_tree = null
		current_quickbar = null
		item_inventory = ItemInventory.new()
		consumable_inventory = ConsumableInventory.new()
		potion_belt = PotionBelt.new()
		offline_xp_tracker = OfflineXPTracker.new()
		dungeon_run_controller = null
		return
	_hydrate_active_character(target)
	# Persist the new active slot to disk. Without this, an immediately-
	# subsequent Nakama auth fires _on_nakama_authenticated, which reads the
	# stale on-disk active_slot, merges, and rebuilds current_character from
	# the *previous* slot — silently swapping the player's chosen co-op class
	# back to whatever was active before they tapped this card. Save now so
	# the merge reads the slot we just switched to.
	SaveManager.save_from_state()

func apply_merged_save(save_data: KittenSaveData) -> void:
	var c := CharacterData.new()
	save_data.apply_to(c)
	current_character = c
	skill_tree = _build_tree_for(c)
	skill_tree.apply_unlocked_ids(save_data.unlocked_skill_ids)
	# Top up any level-gated unlocks the save predates (PRD #124 / issue #126).
	# Idempotent against already-unlocked ids restored from the save.
	SkillUnlockCheckerRef.auto_unlock_for_level(skill_tree, current_character.level)
	meta_tracker = save_data.to_tracker()
	offline_xp_tracker = save_data.to_offline_xp_tracker()
	cosmetic_inventory = save_data.to_cosmetic_inventory()
	paid_unlocks = save_data.to_paid_unlock_inventory()
	currency_ledger = save_data.to_currency_ledger()
	skill_inventory = save_data.to_skill_inventory()
	item_inventory = save_data.to_item_inventory()
	CharacterMutator.new(current_character).apply_item_bonuses(item_inventory)
	# Resume an in-flight solo dungeon run (PRD #42 / #46). When the saved
	# state is empty (legacy save / no run in flight / multiplayer-only) the
	# serializer returns null and main_scene falls through to
	# _start_new_dungeon. The serializer regenerates the dungeon from the
	# stored seed, advances the controller to the saved room, and replays
	# explicit clears.
	dungeon_run_controller = DungeonRunSerializerRef.deserialize(save_data.dungeon_run_state)
	# Build the quickbar AFTER unlocks are applied + leveled-up nodes are
	# topped up, so the legacy-save migration path inside to_quickbar() walks
	# the correct set of unlocked spells. The slice 5 acceptance criterion
	# "pre-feature saves load and auto-fill from already-unlocked spells in
	# tree order" relies on this ordering.
	current_quickbar = save_data.to_quickbar(skill_tree)
	consumable_inventory = save_data.to_consumable_inventory()
	potion_belt = save_data.to_potion_belt()
	streak_day = save_data.streak_day
	last_login_date = save_data.last_login_date

func _on_nakama_authenticated(p_session: NakamaSession) -> void:
	account_manager.sign_in(p_session.user_id)
	local_player_id = p_session.user_id
	# Slice 6 (PRD #250): sync the whole SaveBundle as one combined document,
	# not the flat KittenSaveData. Account-wide unlocks union, per-slot offline
	# XP folds in at equal level, slots-on-one-side carry through.
	var local_bundle := SaveManager.load_bundle()
	var server_dict: Dictionary = await NakamaService.fetch_save_async(p_session)
	var server_bundle: SaveBundle = null
	if not server_dict.is_empty():
		server_bundle = SaveBundle.from_dict(server_dict)
	var merged_bundle: SaveBundle = SaveSyncOrchestrator.sync_bundle(local_bundle, server_bundle, offline_xp_tracker)
	if merged_bundle == null:
		return
	# Zero per-slot offline_xp_earned on the merged bundle — the delta is
	# already baked into each slot's xp (via the equal-level fold or the
	# level-resolve clone), so the "since last sync" window resets on both
	# stores.
	for key in merged_bundle.slots.keys():
		var s: CharacterSlotData = merged_bundle.slots[key]
		if s != null:
			s.offline_xp_earned = 0
	SaveManager.save_bundle(merged_bundle)
	# Rehydrate live state from the merged bundle so the in-memory account /
	# active character match what we just wrote to disk + are about to upload.
	var merged_flat := KittenSaveData.from_bundle(merged_bundle)
	apply_merged_save(merged_flat)
	await NakamaService.upload_save_async(p_session, merged_bundle.to_dict())
	save_synced.emit(merged_flat)

# Builds the per-player_id character map a CoopSession is constructed from
# (issue #255). Keyed by this client's local_player_id; the value is the live
# active-slot character so its real level/stats drive PartyScaler.compute_floor
# and the in-match scaling — not a default level-1 battle kitten. The lobby's
# match-start handler hands this to CoopSession.new. Returns an empty map when
# there's no active character or no known local id (pre-handshake / solo).
func build_coop_chars_map() -> Dictionary:
	var chars: Dictionary = {}
	if current_character != null and local_player_id != "":
		chars[local_player_id] = current_character
	return chars

func set_character(c: CharacterData) -> void:
	current_character = c
	# item_inventory is a persistent autoload field. Reset it for a brand-new
	# character so it doesn't inherit the previous character's equipped gear
	# (a fresh Wizard would otherwise show up holding the prior Battle kitten's
	# sword). The save-load paths (_hydrate_active_character / apply_merged_save)
	# rebuild item_inventory from the slot themselves, so this only affects the
	# character-creation entry point.
	item_inventory = ItemInventory.new()
	# Brand-new character starts with no potion stacks and an empty belt so it
	# doesn't inherit the previous character's potions across a slot swap.
	consumable_inventory = ConsumableInventory.new()
	potion_belt = PotionBelt.new()
	skill_tree = _build_tree_for(c)
	# Issue #126 AC1: a freshly-created level-1 character enters their first
	# dungeon with the level_required == 1 node already unlocked. Runs for any
	# level (tier-2 upgrade paths reuse this entry point) so a character handed
	# in at level N has every node up through N unlocked.
	SkillUnlockCheckerRef.auto_unlock_for_level(skill_tree, c.level)
	# Brand-new character has no persisted quickbar — auto-fill the lowest
	# empty slots from whatever spells just got unlocked by the level-gated
	# pass above. Mirrors the slice-2 Player bootstrap so user story 16
	# ("first spell auto-placed in slot 1") holds without a save round-trip.
	current_quickbar = Quickbar.new()
	for spell in skill_tree.get_unlocked_spells():
		current_quickbar.on_spell_unlocked(spell)

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
	consumable_inventory = ConsumableInventory.new()
	potion_belt = PotionBelt.new()
	current_quickbar = null
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
	streak_day = 0
	last_login_date = ""

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
		lobby.taunt_received.connect(_on_taunt_received)
		lobby.heal_received.connect(_on_heal_received)
		lobby.damage_received.connect(_on_damage_received)
		lobby.host_paused.connect(_on_host_paused)
		lobby.host_unpaused.connect(_on_host_unpaused)

func _disconnect_lobby_signals(old: NakamaLobby) -> void:
	if old.position_received.is_connected(_on_position_received):
		old.position_received.disconnect(_on_position_received)
	if old.kill_received.is_connected(_on_kill_received):
		old.kill_received.disconnect(_on_kill_received)
	if old.taunt_received.is_connected(_on_taunt_received):
		old.taunt_received.disconnect(_on_taunt_received)
	if old.heal_received.is_connected(_on_heal_received):
		old.heal_received.disconnect(_on_heal_received)
	if old.damage_received.is_connected(_on_damage_received):
		old.damage_received.disconnect(_on_damage_received)
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

func _on_position_received(player_id: String, position: Vector2, _timestamp: float, _facing_x: int) -> void:
	# Facing is fanned to RemoteKitten by CoopPlayerLayer (which subscribes
	# to the same signal); GameState's job is to keep the network sync
	# manager driving the interpolated position. Splitting the two routes
	# avoids needing a CoopPlayerLayer reference on the autoload.
	#
	# PRD #338 fix: stamp the sample with the *receiver's* local clock at
	# arrival, not the sender's wire `_timestamp`. Sender/receiver clocks
	# come from different processes with no shared origin, so feeding the
	# wire ts into the interpolator produced an undefined lerp window
	# (root cause of the choppy remote-kitten rendering). The wire field
	# remains present on the packet for forward compatibility but is no
	# longer consumed for receive-side timing.
	if coop_session == null or coop_session.network_sync == null:
		return
	var arrival_time: float = Time.get_ticks_msec() / 1000.0
	coop_session.network_sync.apply_remote_state(player_id, position, arrival_time)

# Inbound kill bridge — wire packet → RemoteKillApplier (data side) +
# RemoteEnemyDespawner (scene side). apply_death's idempotent gate rejects
# duplicate packets; xp_broadcaster fans XP to every party member's
# CoopXPSubscriber (the local player picks its own emission and applies to
# member.real_stats). Solo path / pre-session (coop_session == null) is a
# silent no-op via RemoteKillApplier's own null-check.
#
# Despawn is gated on RemoteKillApplier's rising-edge true return so a
# duplicate packet doesn't re-scan the scene tree for an already-freed
# node. AC#4 ("no ghost enemies") closes here: the visible Enemy
# CharacterBody2D disappears in lockstep with the registry update.
func _on_kill_received(enemy_id: String, killer_id: String, xp_value: int, is_boss: bool = false) -> void:
	# TEMP co-op QA instrumentation (issue #352). Remove after QA.
	var _applied := RemoteKillApplier.apply(coop_session, enemy_id, killer_id, xp_value)
	if not _applied:
		print("[coop-enemy] KILL recv id=%s GATED (apply_death false: already-dead/unregistered)" % enemy_id)
		return
	var _freed := RemoteEnemyDespawner.despawn(get_tree(), enemy_id)
	print("[coop-enemy] KILL recv id=%s applied=true despawn_freed=%s" % [enemy_id, str(_freed)])
	# Slice 7 (PRD #201): co-op drop fan-out. Each receiving client rolls
	# its own item drop locally against current_character — independent of
	# whatever the killer rolled, so every party member gets a class-
	# appropriate drop. The roll is gated behind RemoteKillApplier's
	# rising-edge true return so a duplicate packet doesn't double-roll.
	# The killer's own drop is handled by KillRewardRouter on the sender
	# side and never re-rolls here (self-echo dropped at NakamaLobby
	# routing layer via sender_id == local_player_id).
	_resolve_remote_item_drop(is_boss)

func _resolve_remote_item_drop(is_boss: bool) -> void:
	if current_character == null:
		return
	var item := _RemoteItemDropResolverRef.resolve(current_character, is_boss, null)
	if item == null:
		return
	# Reuse the local Player's item_dropped signal so the existing single-
	# player drop path (HUD._on_player_item_dropped → item_inventory.add_to
	# _bag + floating "Looted" text) takes over without duplicating the
	# auto-bag wiring here. Group lookup mirrors RemoteHealApplier /
	# RemoteTauntApplier — node-by-group, not by id. Between scenes (no
	# Player in tree) the drop silently falls on the floor, matching the
	# despawn path's "no tree, no scene-side effect" contract.
	var tree := get_tree()
	if tree == null:
		return
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0]
	if not player.has_signal("item_dropped"):
		return
	player.item_dropped.emit(item)

# Inbound TAUNT bridge — wire packet → RemoteTauntApplier (data side).
# The applier walks the "enemies" group and stamps taunt_source_id +
# taunt_remaining on the matching local Enemy so the future
# Enemy._select_taunt_target lookup-by-id branch has identity to match
# against. NOT stamped: taunt_target (CharacterData reference the
# receiving client doesn't have — that's the next slice). Solo / pre-
# scene-add paths are silent no-ops via RemoteTauntApplier's null-tree
# guard.
func _on_taunt_received(caster_id: String, enemy_id: String, duration: float) -> void:
	RemoteTauntApplier.apply(get_tree(), caster_id, enemy_id, duration)

# Inbound HEAL/buff bridge — wire packet → RemoteHealApplier (data side).
# The applier walks the "players" group and dispatches by effect_kind:
# instant heals via CharacterData.heal, GROUP_REGEN / PARTY_BUFF_* via
# add_buff. Solo / pre-scene-add paths are silent no-ops via the
# applier's null-tree guard. Self-echo dropping happens upstream in
# NakamaLobby._route_heal so the local resolver's already-applied effect
# isn't double-stacked here. caster_id is unused by the applier today
# (the receiver doesn't need to know who cast — heal/buff effects don't
# carry attribution like XP does) but stays in the signal payload for
# future hooks (e.g. floating-text "Player X healed you").
func _on_heal_received(_caster_id: String, target_id: String, effect_kind: String, amount: int, duration: float) -> void:
	_RemoteHealApplierRef.apply(get_tree(), target_id, effect_kind, amount, duration)

# Inbound damage-dealt bridge (PRD #328 slice 6, issue #334). wire packet
# → RemoteDamageVisualizer. Spawns the same FloatingText overlay solo uses
# at the matching enemy's world position so every peer sees a teammate's
# hit number floating above the target. attacker_id is unused today (the
# number itself is identical regardless of who threw it); reserved for a
# future "color the number per-attacker" visual without a wire break.
# Missing enemy (already despawned on receiver) is the visualizer's
# silent-false-return — AC#6 holds without extra guard here.
func _on_damage_received(_attacker_id: String, enemy_id: String, damage: int, kind: int) -> void:
	_RemoteDamageVisualizerRef.spawn(get_tree(), enemy_id, damage, kind)
	# Shared enemy health bars (PRD #341, issue #342). The visualizer above
	# paints the floating number; this call subtracts the same damage from
	# the matching local Enemy.data.hp so the polled enemy_health_bar /
	# boss_health_bar drops on every peer's screen. Self-echo is dropped at
	# NakamaLobby._route_damage_dealt (sender_id == local_player_id), so the
	# attacker never double-decrements their own HP copy.
	var _hit := _RemoteEnemyDamageApplierRef.apply(get_tree(), enemy_id, damage)
	# TEMP co-op QA instrumentation (issue #352). Remove after QA. _hit=false
	# means no local enemy node carried this enemy_id — the spawns desynced.
	print("[coop-enemy] DMG recv id=%s dmg=%d matched_local_enemy=%s" % [enemy_id, damage, str(_hit)])

# Per-class tree builder (PRD #124 / issue #127). Each Kitten archetype has
# its own 5-node factory. Cat-tier classes share their Kitten counterpart's
# tree so a tier-2 upgrade preserves unlocks. Unknown class falls through to
# the Battle Kitten tree as a safe default — better than returning null and
# forcing every call site to null-check.
func _build_tree_for(c: CharacterData) -> SkillTree:
	match c.character_class:
		CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT:
			return SkillTree.make_battle_kitten_tree()
		CharacterData.CharacterClass.WIZARD_KITTEN, CharacterData.CharacterClass.WIZARD_CAT:
			return SkillTree.make_wizard_kitten_tree()
		CharacterData.CharacterClass.SLEEPY_KITTEN, CharacterData.CharacterClass.SLEEPY_CAT:
			return SkillTree.make_sleepy_kitten_tree()
		CharacterData.CharacterClass.CHONK_KITTEN, CharacterData.CharacterClass.CHONK_CAT:
			return SkillTree.make_chonk_kitten_tree()
	return SkillTree.make_battle_kitten_tree()
