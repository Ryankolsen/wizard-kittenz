class_name AccountSaveData
extends RefCounted

# Account-wide save fields — one of these per save bundle, shared across every
# character slot. Carved out of the legacy KittenSaveData per PRD #250 so
# things the player earned/bought on the account (gold, gems, paid unlocks,
# meta-progression, daily streak) survive a per-character New Game.

var gold_balance: int = 0
var gem_balance: int = 0
var paid_class_unlocks: Array = []
var cosmetic_packs: Array = []
var skill_unlocks: Array = []
var max_level_per_class: Dictionary = {}
var dungeons_completed: int = 0
var cleared_dungeons: Array = []
var streak_day: int = 0
var last_login_date: String = ""

# Snapshot live account-wide state. Used by SaveManager.save_from_state to
# assemble the AccountSaveData portion of the SaveBundle (PRD #250 / slice 2).
# meta_tracker carries the cleared_dungeons / dungeons_completed / max_level
# fields that previously rode on KittenSaveData.
static func from_state(currency_ledger: CurrencyLedger = null, cosmetic_inv: CosmeticInventory = null, paid_unlocks: PaidUnlockInventory = null, skill_inv = null, meta_tracker: MetaProgressionTracker = null, streak_day: int = 0, last_login_date: String = "") -> AccountSaveData:
	var a := AccountSaveData.new()
	if currency_ledger != null:
		a.gold_balance = currency_ledger.balance(CurrencyLedger.Currency.GOLD)
		a.gem_balance = currency_ledger.balance(CurrencyLedger.Currency.GEM)
	if cosmetic_inv != null:
		a.cosmetic_packs = cosmetic_inv.owned_pack_ids.duplicate()
	if paid_unlocks != null:
		a.paid_class_unlocks = paid_unlocks.owned_class_ids.duplicate()
	if skill_inv != null:
		a.skill_unlocks = skill_inv.owned_skill_ids.duplicate()
	if meta_tracker != null:
		a.dungeons_completed = meta_tracker.dungeons_completed
		a.max_level_per_class = meta_tracker.max_level_per_class.duplicate()
		a.cleared_dungeons = meta_tracker.cleared_dungeons.duplicate()
	a.streak_day = streak_day
	a.last_login_date = last_login_date
	return a

func to_dict() -> Dictionary:
	return {
		"gold_balance": gold_balance,
		"gem_balance": gem_balance,
		"paid_class_unlocks": paid_class_unlocks.duplicate(),
		"cosmetic_packs": cosmetic_packs.duplicate(),
		"skill_unlocks": skill_unlocks.duplicate(),
		"max_level_per_class": max_level_per_class.duplicate(),
		"dungeons_completed": dungeons_completed,
		"cleared_dungeons": cleared_dungeons.duplicate(),
		"streak_day": streak_day,
		"last_login_date": last_login_date,
	}

static func from_dict(d: Dictionary) -> AccountSaveData:
	var a := AccountSaveData.new()
	a.gold_balance = int(d.get("gold_balance", 0))
	a.gem_balance = int(d.get("gem_balance", 0))
	var paid = d.get("paid_class_unlocks", [])
	if paid is Array:
		for raw in paid:
			var key := String(raw).to_lower()
			if key != "" and not a.paid_class_unlocks.has(key):
				a.paid_class_unlocks.append(key)
	var packs = d.get("cosmetic_packs", [])
	if packs is Array:
		a.cosmetic_packs = packs.duplicate()
	var skills = d.get("skill_unlocks", [])
	if skills is Array:
		for raw in skills:
			var key := String(raw).to_lower()
			if key != "" and not a.skill_unlocks.has(key):
				a.skill_unlocks.append(key)
	var per_class = d.get("max_level_per_class", {})
	if per_class is Dictionary:
		for k in per_class.keys():
			a.max_level_per_class[String(k).to_lower()] = int(per_class[k])
	a.dungeons_completed = int(d.get("dungeons_completed", 0))
	var cleared = d.get("cleared_dungeons", [])
	if cleared is Array:
		for raw in cleared:
			var id := String(raw)
			if id != "" and not a.cleared_dungeons.has(id):
				a.cleared_dungeons.append(id)
	a.streak_day = int(d.get("streak_day", 0))
	a.last_login_date = String(d.get("last_login_date", ""))
	return a
