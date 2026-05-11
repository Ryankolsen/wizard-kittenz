class_name DungeonRunCompletion
extends RefCounted

# Single entry point for the "dungeon completed" event. Bumps the meta
# tracker so unlock conditions like "complete N dungeons" advance.
#
# Pure data — no scene tree, no signals. The room-transition layer (which
# owns the boss-cleared signal) calls this from its terminal branch once
# the boss room's last enemy dies. Idempotency is the caller's: the boss
# can only die once per run, so the event fires exactly once naturally.
# Keeping the function NON-idempotent on purpose so a (rare) future
# multi-boss dungeon can call it per boss without a special-case knob.
#
# Null-safe: a fresh-install / test path that hasn't built a meta tracker
# yet is silently ignored. Production paths come through GameState which
# keeps the tracker non-null after _ready.

static func complete(meta_tracker: MetaProgressionTracker) -> void:
	if meta_tracker != null:
		meta_tracker.record_dungeon_complete()
