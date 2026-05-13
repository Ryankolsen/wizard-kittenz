class_name DailyLoginBonus
extends RefCounted

# Daily-login Gem bonus (PRD #53 / issue #68). Pure helper — no autoload
# dependency, today_date injected so tests don't need to fake the system
# clock. try_award is idempotent against the same calendar date: a
# second call with the same today_date is a no-op on both the ledger
# and the save's last_login_date.

const DAILY_LOGIN_GEM_REWARD := 10

# Returns true when the bonus was actually credited (date differed from
# the stored last_login_date), false on the same-day no-op or when the
# inputs are unusable. The caller may use the bool for a "Daily reward!"
# toast affordance without re-reading save state.
static func try_award(save_data: KittenSaveData, ledger: CurrencyLedger, today_date: String) -> bool:
	if save_data == null or ledger == null:
		return false
	if today_date == "":
		return false
	if save_data.last_login_date == today_date:
		return false
	ledger.credit(DAILY_LOGIN_GEM_REWARD, CurrencyLedger.Currency.GEM)
	save_data.last_login_date = today_date
	return true
