class_name DailyStreakSchedule
extends RefCounted

# Pure 30-day rotating reward table for the daily-login streak
# (PRD #237 / issue #238). Maps streak day (1–30) → {type, amount}.
# No state, no clock, no CurrencyLedger or save dependency — the
# engine (#241) and popup preview (#243) read from here.
#
# Curve: types rotate GOLD → XP → GEM. Amounts climb each time a type
# recurs: GOLD +25, XP +15, GEM +3. Day 30 is a 250-gem jackpot
# override (replaces the +3 progression value of 32).
#
# RewardType is defined locally so this module stays decoupled from
# CurrencyLedger.Currency, which has no XP member. The applier (#242)
# is responsible for routing GOLD/GEM → CurrencyLedger and XP → the
# XP tracker.

enum RewardType { GOLD, XP, GEM }

const _GOLD_BASE := 50
const _GOLD_STEP := 25
const _XP_BASE := 25
const _XP_STEP := 15
const _GEM_BASE := 5
const _GEM_STEP := 3
const _JACKPOT_DAY := 30
const _JACKPOT_AMOUNT := 250

# Returns {"type": RewardType, "amount": int}. Out-of-range days clamp
# to [1, 30] rather than crash — the engine never asks for days outside
# the 1-30 window, but the popup preview probes day+1/+2/+3 and can
# legitimately overshoot 30 near the end of a streak.
static func reward_for(day: int) -> Dictionary:
	var d := clampi(day, 1, _JACKPOT_DAY)
	if d == _JACKPOT_DAY:
		return {"type": RewardType.GEM, "amount": _JACKPOT_AMOUNT}
	var slot := (d - 1) % 3  # 0=GOLD, 1=XP, 2=GEM
	var occurrence := (d - 1) / 3  # 0-based count of this type before today
	match slot:
		0:
			return {"type": RewardType.GOLD, "amount": _GOLD_BASE + _GOLD_STEP * occurrence}
		1:
			return {"type": RewardType.XP, "amount": _XP_BASE + _XP_STEP * occurrence}
		_:
			return {"type": RewardType.GEM, "amount": _GEM_BASE + _GEM_STEP * occurrence}
