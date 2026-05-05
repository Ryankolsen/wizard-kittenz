class_name DungeonRunCompletion
extends RefCounted

# Single entry point for the "dungeon completed" event. Bundles the two
# side effects the boss-room-cleared hook fires: bumps the meta tracker
# (so unlock conditions like "complete N dungeons" advance) and drips the
# dungeon-complete revive token. Returns the count granted so the caller
# can surface a "+N tokens" toast.
#
# Pure data — no scene tree, no signals. The room-transition layer (which
# owns the boss-cleared signal) calls this from its terminal branch once
# the boss room's last enemy dies. Idempotency is the caller's: the boss
# can only die once per run, so the event fires exactly once naturally.
# Keeping the function NON-idempotent on purpose so a (rare) future
# multi-boss dungeon can call it per boss without a special-case knob.
#
# Null-safe on both args: a fresh-install / test path that hasn't built a
# meta tracker or token inventory yet still returns 0 cleanly. Production
# paths come through GameState which keeps both non-null after _ready.

static func complete(meta_tracker: MetaProgressionTracker, inventory: TokenInventory) -> int:
	if meta_tracker != null:
		meta_tracker.record_dungeon_complete()
	if inventory == null:
		return 0
	return inventory.grant(TokenGrantRules.tokens_for_dungeon_complete())
