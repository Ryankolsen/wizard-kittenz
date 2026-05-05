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
