class_name SaveSyncOrchestrator
extends RefCounted

# Single entry point for the sign-in / reconnect sync step. Bundles the three
# primitives that always fire together when the local save meets a server
# copy:
#   1. OfflineProgressMerger.resolve  — picks the higher-level winner
#   2. OfflineProgressMerger.merge_xp — folds local.offline_xp_earned into
#      the server's record when levels match (so XP earned offline that
#      didn't cross a level isn't lost on reconnect)
#   3. OfflineXPTracker.clear()       — resets the "since last sync" window
#      so the next solo kill starts from zero
#
# Returns the merged KittenSaveData (a fresh clone — caller can mutate freely
# without stealth-mutating either input). Pure data layer: no I/O, no Nakama.
# When the wire layer (#14) lands, the orchestrator call site is roughly:
#
#   var local := SaveManager.load()
#   var server := KittenSaveData.from_dict(nakama.fetch_save())
#   var merged := SaveSyncOrchestrator.sync(local, server, GameState.offline_xp_tracker)
#   if merged != null:
#       SaveManager.save(...)        # writes merged back locally
#       nakama.upload_save(merged.to_dict())
#
# Pure RefCounted with one static — same shape as DungeonRunCompletion /
# KillRewardRouter. No state, no construction.

# Bundles resolve + merge_xp + tracker.clear into one call. Returns the
# merged record the caller writes to both stores; clears the tracker as a
# side effect once the merge is settled.
#
# Cases:
# - both null: nothing exists anywhere. Return null. Tracker is NOT cleared
#   (no sync happened — clearing here would erase pending XP if the wire
#   layer hands us null for a transient fetch failure).
# - local null, server non-null: brand-new device, server is canonical.
#   Returns a clone of server. Tracker is left alone — there's no local
#   gameplay to flush, and the tracker is empty by convention on a fresh
#   install anyway.
# - local non-null, server null: brand-new account / first-sync-up. Local
#   is the upload payload. Tracker clears because the offline window just
#   "synced" (the wire layer uploads the merged record).
# - both non-null: standard sync. Equal level -> merge_xp folds the offline
#   delta in. Differing level -> resolve picks the higher; the offline
#   delta is already baked into local.xp / local.level so no merge_xp.
#   Tracker clears in either branch.
static func sync(local: KittenSaveData, server: KittenSaveData, tracker: OfflineXPTracker = null) -> KittenSaveData:
	if local == null and server == null:
		return null
	var result: KittenSaveData
	if local == null:
		# Brand-new device: server is the canonical record. No local
		# gameplay to fold in, no tracker state to flush.
		return _clone(server)
	if server == null:
		# Brand-new account / first sync-up: local is canonical.
		result = _clone(local)
	elif local.level == server.level:
		# Equal level: merge_xp folds local.offline_xp_earned into a
		# fresh server clone. Catches the "earned XP offline but didn't
		# level up" case so XP isn't lost on reconnect.
		result = OfflineProgressMerger.merge_xp(local, server)
	else:
		# Levels differ: resolve picks the higher. The losing side's
		# offline_xp_earned is implicitly baked into the winner already
		# (if local won, into local.xp; if server won, the local delta
		# is being abandoned along with the rest of the lower-level
		# local progression — same call to write up to the new account
		# context).
		result = _clone(OfflineProgressMerger.resolve(local, server))
	# Always clear the tracker once we've produced a merged result. The
	# wire layer is responsible for actually persisting + uploading; if
	# either step fails the next sync attempt re-fetches and re-merges
	# from the (post-clear) tracker, which is correct because the
	# pending_xp delta has already been folded into the in-memory result.
	# Re-applying it would double-count.
	if tracker != null:
		tracker.clear()
	return result

# Round-trips through to_dict / from_dict so the caller can mutate the
# returned record without stealth-mutating either input. Cheap because
# KittenSaveData is already a flat JSON-shaped record.
static func _clone(s: KittenSaveData) -> KittenSaveData:
	return KittenSaveData.from_dict(s.to_dict())

# ----- Bundle-level sync (PRD #250 / slice 6) -------------------------------
#
# Cases match the kitten path:
# - both null: nothing exists anywhere → null. Tracker is NOT cleared.
# - local null, server non-null: brand-new device, server is canonical →
#   clone(server). Tracker is left alone.
# - local non-null, server null: brand-new account / first sync-up →
#   clone(local). Tracker clears.
# - both non-null: account-wide merge (union/max) + per-slot merge (level
#   resolve + offline-xp fold at equal level). Tracker clears.
# Bundle-level sync (PRD #250 / slice 6): one combined document covering both
# account-wide fields (union/max) and per-slot fields (level resolve +
# offline-xp fold at equal level). Returns a fresh SaveBundle the caller can
# mutate without stealth-mutating either input.
static func sync_bundle(local: SaveBundle, server: SaveBundle, tracker: OfflineXPTracker = null) -> SaveBundle:
	if local == null and server == null:
		return null
	if local == null:
		return _clone_bundle(server)
	if server == null:
		var only_local := _clone_bundle(local)
		if tracker != null:
			tracker.clear()
		return only_local
	var merged := SaveBundle.new()
	merged.version = max(local.version, server.version)
	merged.account = _merge_account(local.account, server.account)
	# active_slot: prefer local (the device the player is currently on); fall
	# back to server if local has none.
	merged.active_slot = local.active_slot if local.active_slot != "" else server.active_slot
	# Per-slot merge across the union of slot keys.
	var keys := {}
	for k in local.slots.keys():
		keys[k] = true
	for k in server.slots.keys():
		keys[k] = true
	for key in keys.keys():
		var ls: CharacterSlotData = local.slots.get(key, null)
		var ss: CharacterSlotData = server.slots.get(key, null)
		merged.slots[key] = _merge_slot(ls, ss)
	if tracker != null:
		tracker.clear()
	return merged

static func _merge_account(local: AccountSaveData, server: AccountSaveData) -> AccountSaveData:
	if local == null and server == null:
		return AccountSaveData.new()
	if local == null:
		return AccountSaveData.from_dict(server.to_dict())
	if server == null:
		return AccountSaveData.from_dict(local.to_dict())
	var out := AccountSaveData.new()
	# Owned-unlock sets: union so a purchase on either device is never lost.
	out.paid_class_unlocks = _union_array(local.paid_class_unlocks, server.paid_class_unlocks)
	out.cosmetic_packs = _union_array(local.cosmetic_packs, server.cosmetic_packs)
	out.skill_unlocks = _union_array(local.skill_unlocks, server.skill_unlocks)
	out.cleared_dungeons = _union_array(local.cleared_dungeons, server.cleared_dungeons)
	# Monotonic counters: max.
	out.streak_day = max(local.streak_day, server.streak_day)
	out.dungeons_completed = max(local.dungeons_completed, server.dungeons_completed)
	# Per-class max level.
	for k in local.max_level_per_class.keys():
		out.max_level_per_class[k] = int(local.max_level_per_class[k])
	for k in server.max_level_per_class.keys():
		var sv := int(server.max_level_per_class[k])
		out.max_level_per_class[k] = max(int(out.max_level_per_class.get(k, 0)), sv)
	# last_login_date: later date wins (ISO 8601 sorts lexicographically).
	out.last_login_date = local.last_login_date if local.last_login_date >= server.last_login_date else server.last_login_date
	# gold / gem: last-write-wins via last_login_date. Concurrent spend/earn
	# reconciliation is explicitly out of scope per PRD #250.
	var local_is_newer := local.last_login_date >= server.last_login_date
	out.gold_balance = local.gold_balance if local_is_newer else server.gold_balance
	out.gem_balance = local.gem_balance if local_is_newer else server.gem_balance
	return out

static func _merge_slot(local: CharacterSlotData, server: CharacterSlotData) -> CharacterSlotData:
	# Slot present on only one side carries through.
	if local == null and server == null:
		return null
	if local == null:
		return CharacterSlotData.from_dict(server.to_dict())
	if server == null:
		return CharacterSlotData.from_dict(local.to_dict())
	# Both sides have this slot: reuse level-based resolve + merge_xp.
	if local.level == server.level:
		var out := CharacterSlotData.from_dict(server.to_dict())
		if local.offline_xp_earned > 0:
			out.xp = server.xp + local.offline_xp_earned
		return out
	if local.level > server.level:
		return CharacterSlotData.from_dict(local.to_dict())
	return CharacterSlotData.from_dict(server.to_dict())

static func _clone_bundle(b: SaveBundle) -> SaveBundle:
	return SaveBundle.from_dict(b.to_dict())

static func _union_array(a: Array, b: Array) -> Array:
	var out: Array = []
	for item in a:
		if not out.has(item):
			out.append(item)
	for item in b:
		if not out.has(item):
			out.append(item)
	return out
