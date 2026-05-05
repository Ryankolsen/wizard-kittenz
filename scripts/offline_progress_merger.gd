class_name OfflineProgressMerger
extends RefCounted

# Resolves the conflict between a locally-saved KittenSaveData and a server
# (Nakama, post-#14) copy when the player signs back in. Pure data layer —
# no Nakama, no SaveManager I/O. The sync orchestrator (lands with #14)
# loads both copies, calls resolve() to pick the winner for the headline
# fields (level, character_class, etc.) and merge_xp() to fold any
# offline-earned XP that didn't change a level into the result.
#
# Conflict rule: higher level wins outright. Ties go to the local copy
# because local is "what the player sees right now" — preferring it
# avoids the worst UX bug, which is "signed in and my last 30 minutes
# vanished." The server overrides only when it's strictly newer (level
# strictly higher), which can only happen if the player played on
# another device.

# Returns the save that should be treated as the authoritative current
# state. Higher level wins; on tie, local wins.
#
# When the saves are at equal level, callers typically follow up with
# merge_xp() to fold local.offline_xp_earned into the result. resolve()
# itself does NOT touch xp — it's a pure pick between two whole records.
static func resolve(local: KittenSaveData, server: KittenSaveData) -> KittenSaveData:
	if local == null and server == null:
		return null
	if local == null:
		return server
	if server == null:
		return local
	if local.level > server.level:
		return local
	if server.level > local.level:
		return server
	return local

# Folds local.offline_xp_earned into a fresh copy of server. Returns
# the merged record without mutating either input.
#
# Only meaningful when local.level == server.level — that's the
# "didn't level up offline, but did earn some XP" case where the
# server's xp counter just hasn't seen the offline gameplay yet.
# When levels differ, resolve() already picked a winner; merge_xp on
# differing levels is a no-op (returns a clone of server) because the
# offline XP is already baked into local.xp / local.level.
#
# offline_xp_earned <= 0 is also a no-op (returns a clone of server)
# so a save with no offline activity merges cleanly.
static func merge_xp(local: KittenSaveData, server: KittenSaveData) -> KittenSaveData:
	if server == null:
		return null
	var merged := _clone(server)
	if local == null:
		return merged
	if local.level != server.level:
		return merged
	if local.offline_xp_earned <= 0:
		return merged
	merged.xp = server.xp + local.offline_xp_earned
	return merged

# Round-trips through to_dict / from_dict so the merged record is
# decoupled from the originals (mutating one input later doesn't
# stealth-mutate the merged result). Cheap because KittenSaveData is
# already a flat JSON-shaped record.
static func _clone(s: KittenSaveData) -> KittenSaveData:
	return KittenSaveData.from_dict(s.to_dict())
