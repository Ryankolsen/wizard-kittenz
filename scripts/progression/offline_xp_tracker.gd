class_name OfflineXPTracker
extends RefCounted

# Counts XP earned in the solo path since the last server sync.
# OfflineProgressMerger.merge_xp folds pending_xp into the server record on
# reconnect when local.level == server.level. The sync orchestrator
# (post-#14) calls clear() after a successful merge so the next solo kill
# starts from zero.
#
# Co-op path is intentionally a no-op for offline tracking — co-op requires
# the network, so any XP earned in a co-op session is already "synced" in
# the sense that it happened with network access. KillRewardRouter only
# calls record() in the solo branch.
#
# Pure RefCounted, same shape as MetaProgressionTracker (thin wrapper
# around an int with a JSON projection via KittenSaveData). Not stored
# as a Resource because saves are JSON-shaped (KittenSaveData), not
# .tres-shaped (CharacterData).

var pending_xp: int = 0

# Tally an XP award. Returns the new pending total. Non-positive amounts
# are no-ops so a future "scaled XP debuff" path can't accidentally
# decrement the counter — the merge logic assumes pending_xp is the
# amount the server is missing, never a refund.
func record(amount: int) -> int:
	if amount <= 0:
		return pending_xp
	pending_xp += amount
	return pending_xp

# Resets the counter to zero. Returns the previous total so the sync
# orchestrator can log "+N XP merged" without re-reading pending_xp before
# the call.
func clear() -> int:
	var prev := pending_xp
	pending_xp = 0
	return prev

func is_empty() -> bool:
	return pending_xp == 0
