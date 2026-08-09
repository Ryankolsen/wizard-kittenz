class_name GwendolynCooldown
extends RefCounted

# Pure real-world-time cooldown resolver for Summon Gwendolyn (PRD #474 /
# issue #477). Every existing cooldown is either an instant in-run timer
# (Spell.cooldown_remaining) or calendar-day granularity
# (DailyStreakEngine); this compares a persisted last-used unix timestamp
# against "now" at a rolling hour-granularity window instead. Stateless and
# per-character: callers pass whichever character's last_used value they
# care about, so two characters never share a cooldown.

const COOLDOWN_SECONDS := 3600

# last_used accepts an int unix timestamp, or null/0/negative for "never
# used" — mirrors DailyStreakEngine's null-safe resolve() contract by
# reading anything unset/invalid as ready rather than throwing.
static func is_ready(last_used, now_unix: int) -> bool:
	if last_used == null:
		return true
	var last := int(last_used)
	if last <= 0:
		return true
	# Inclusive boundary: exactly COOLDOWN_SECONDS elapsed already counts as
	# ready, so a cast exactly 1 hour ago is not blocked.
	return now_unix - last >= COOLDOWN_SECONDS

static func time_remaining(last_used, now_unix: int) -> int:
	if last_used == null:
		return 0
	var last := int(last_used)
	if last <= 0:
		return 0
	return maxi(0, COOLDOWN_SECONDS - (now_unix - last))
