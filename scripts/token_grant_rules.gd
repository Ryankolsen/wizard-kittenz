class_name TokenGrantRules
extends RefCounted

# Where tokens come from in gameplay. Keeps the "how many?" knobs in one
# place so tuning doesn't ripple through call sites. Pure data — no state,
# no inventory mutation here. Call sites read the count and grant it
# explicitly.

const TOKENS_PER_BOSS_KILL: int = 1
const TOKENS_PER_DUNGEON_COMPLETE: int = 1
const TOKENS_PER_MILESTONE_LEVEL: int = 1
# Every Nth level is a milestone. 5 keeps the early game (L1-4) free of the
# meta-currency drip; first reward is at L5, then L10, L15, ...
const MILESTONE_LEVEL_INTERVAL: int = 5

static func tokens_for_boss_kill() -> int:
	return TOKENS_PER_BOSS_KILL

static func tokens_for_dungeon_complete() -> int:
	return TOKENS_PER_DUNGEON_COMPLETE

# Number of tokens earned for crossing milestone levels in the open-closed
# range (old_level, new_level]. A multi-level XP dump that spans more than
# one milestone (e.g. L4 -> L11) awards multiple tokens. Returns 0 when
# new_level <= old_level so the caller can reuse it post-add_xp without a
# wrapping conditional.
static func tokens_for_level_up(old_level: int, new_level: int) -> int:
	if new_level <= old_level:
		return 0
	var milestones := 0
	for lvl in range(old_level + 1, new_level + 1):
		if lvl > 0 and lvl % MILESTONE_LEVEL_INTERVAL == 0:
			milestones += 1
	return milestones * TOKENS_PER_MILESTONE_LEVEL
