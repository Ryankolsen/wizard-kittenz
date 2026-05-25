class_name DailyStreakEngine
extends RefCounted

# Pure streak resolver for the daily-login streak (PRD #237 / issue #241).
# Replaces the flat 10-gem DailyLoginBonus. Given (save_data, today_date),
# decides what should happen and returns a result dict describing the
# action, resolved day, and reward (via DailyStreakSchedule).
#
# This module updates two save fields — streak_day and last_login_date —
# because those are the streak's own bookkeeping. It does NOT touch the
# currency ledger or XP tracker; the reward applier (#242) routes the
# returned reward to whichever subsystem holds it. Keeping currency
# mutation out of here lets the popup (#243) call resolve() to preview
# without granting anything.

enum Action { CLAIM, RESET_THEN_CLAIM, ALREADY_CLAIMED }
enum ResetReason { NONE, MISSED, CYCLE_COMPLETE }

const _CYCLE_LENGTH := 30

# Returns a result Dictionary with keys:
#   action         : Action
#   day            : int (1–30 for CLAIM/RESET_THEN_CLAIM, 0 for inert)
#   reward         : Dictionary (DailyStreakSchedule.reward_for(day); {} when inert)
#   reset_reason   : ResetReason (NONE unless action == RESET_THEN_CLAIM)
#   previous_streak: int (the streak length before the reset; 0 otherwise)
#
# Null save / null/empty today_date → inert ALREADY_CLAIMED result so the
# call site can treat the engine as crash-proof. Same calendar date as
# the stored last_login_date → ALREADY_CLAIMED with the current streak_day,
# no state change.
static func resolve(save_data: KittenSaveData, today_date) -> Dictionary:
	if save_data == null:
		return _inert()
	if typeof(today_date) != TYPE_STRING or String(today_date) == "":
		return _inert()

	if save_data.last_login_date == today_date:
		return {
			"action": Action.ALREADY_CLAIMED,
			"day": save_data.streak_day,
			"reward": {},
			"reset_reason": ResetReason.NONE,
			"previous_streak": 0,
		}

	var prev_day := save_data.streak_day
	var last_date := save_data.last_login_date

	# First-ever login (or legacy save with streak_day == 0) → start at Day 1.
	if last_date == "" or prev_day <= 0:
		return _commit_claim(save_data, today_date, 1)

	# Day-30 completion resets silently on the next login, regardless of gap.
	if prev_day >= _CYCLE_LENGTH:
		return _commit_reset(save_data, today_date, prev_day, ResetReason.CYCLE_COMPLETE)

	var gap := _day_diff(last_date, today_date)
	if gap == 1:
		return _commit_claim(save_data, today_date, prev_day + 1)

	# gap > 1 (missed a calendar day) or gap <= 0 (clock-rewind / unparseable) →
	# treat as a broken streak. Engine doesn't try to be clever about rewinds;
	# the PRD accepts device-clock exploit risk.
	return _commit_reset(save_data, today_date, prev_day, ResetReason.MISSED)


static func _commit_claim(save_data: KittenSaveData, today_date: String, new_day: int) -> Dictionary:
	save_data.streak_day = new_day
	save_data.last_login_date = today_date
	return {
		"action": Action.CLAIM,
		"day": new_day,
		"reward": DailyStreakSchedule.reward_for(new_day),
		"reset_reason": ResetReason.NONE,
		"previous_streak": 0,
	}


static func _commit_reset(save_data: KittenSaveData, today_date: String, prev_day: int, reason: int) -> Dictionary:
	save_data.streak_day = 1
	save_data.last_login_date = today_date
	return {
		"action": Action.RESET_THEN_CLAIM,
		"day": 1,
		"reward": DailyStreakSchedule.reward_for(1),
		"reset_reason": reason,
		"previous_streak": prev_day,
	}


static func _inert() -> Dictionary:
	return {
		"action": Action.ALREADY_CLAIMED,
		"day": 0,
		"reward": {},
		"reset_reason": ResetReason.NONE,
		"previous_streak": 0,
	}


# Calendar-day delta between two yyyy-mm-dd strings. Uses unix-time math at
# midnight so DST / month-end boundaries are handled by the engine's clock
# rather than ad-hoc arithmetic. Returns -1 for unparseable input so callers
# fall into the reset branch instead of mistakenly treating it as gap == 1.
static func _day_diff(from_iso: String, to_iso: String) -> int:
	var f := _parse_iso(from_iso)
	var t := _parse_iso(to_iso)
	if f.is_empty() or t.is_empty():
		return -1
	var fu := int(Time.get_unix_time_from_datetime_dict(f))
	var tu := int(Time.get_unix_time_from_datetime_dict(t))
	return int(floor(float(tu - fu) / 86400.0))


static func _parse_iso(s: String) -> Dictionary:
	var parts := s.split("-")
	if parts.size() != 3:
		return {}
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {}
	return {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 0,
		"minute": 0,
		"second": 0,
	}
