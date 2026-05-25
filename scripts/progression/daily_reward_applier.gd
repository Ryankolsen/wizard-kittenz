class_name DailyRewardApplier
extends RefCounted

# Routes a daily-streak reward {type, amount} from DailyStreakSchedule /
# DailyStreakEngine (PRD #237 / issue #242) to the subsystem that owns
# the balance. Kept as a thin, tested seam so the engine (#241) stays
# pure and the startup wiring (#244) stays a one-liner.
#
# Routing:
#   GOLD → CurrencyLedger.credit(amount, GOLD)
#   GEM  → CurrencyLedger.credit(amount, GEM)   (Day-30 jackpot is just a normal GEM credit)
#   XP   → OfflineXPTracker.record(amount)      (folds via OfflineProgressMerger.merge_xp
#                                                under the same level == server.level guard
#                                                as solo-kill XP — no new merge logic here)
#
# Empty / malformed / non-positive / unknown-type rewards are safe no-ops
# so callers can pass an inert engine result (e.g. ALREADY_CLAIMED returns
# {}) without branching first.

static func apply(reward: Dictionary, ledger: CurrencyLedger, tracker: OfflineXPTracker) -> void:
	if reward == null or reward.is_empty():
		return
	if not reward.has("type") or not reward.has("amount"):
		return
	var amount := int(reward["amount"])
	if amount <= 0:
		return
	match int(reward["type"]):
		DailyStreakSchedule.RewardType.GOLD:
			if ledger != null:
				ledger.credit(amount, CurrencyLedger.Currency.GOLD)
		DailyStreakSchedule.RewardType.GEM:
			if ledger != null:
				ledger.credit(amount, CurrencyLedger.Currency.GEM)
		DailyStreakSchedule.RewardType.XP:
			if tracker != null:
				tracker.record(amount)
		_:
			pass
