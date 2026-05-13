class_name KittenSaveData
extends RefCounted

# Lightweight JSON-friendly projection of CharacterData. Lives separately from
# CharacterData so the save format can evolve without forcing scene/resource
# migrations. CharacterData is a Resource (.tres-shaped); save state is JSON.

var character_name: String = "Kitten"
var character_class: int = 0
# Sprite-sheet index chosen during character creation. Defaults to 0 so
# legacy saves predating this field round-trip as "first appearance."
var appearance_index: int = 0
var level: int = 1
var xp: int = 0
var hp: int = 0
var max_hp: int = 0
var attack: int = 0
var defense: int = 0
var speed: float = 0.0
var skill_points: int = 0
# Expanded stat set (PRD #52 / issue #55). All new fields default to 0 / 0.0
# so a save written before this PR round-trips with neutral baselines.
var magic_attack: int = 0
var magic_points: int = 0
var max_mp: int = 0
var magic_resistance: int = 0
var dexterity: int = 0
var evasion: float = 0.0
var crit_chance: float = 0.0
var luck: int = 0
var regeneration: int = 0
# Stored as plain Array (not PackedStringArray) so JSON.stringify round-trips
# cleanly via Variant. Snapshot of SkillTree.unlocked_ids() at save time.
var unlocked_skill_ids: Array = []
# Meta-progression snapshot — the tracker's state at save time. Persisted
# alongside the kitten so unlock progress (dungeons cleared, max-level-per-
# class) survives across sessions. Stored as plain primitives so JSON
# round-trips cleanly.
var dungeons_completed: int = 0
var max_level_per_class: Dictionary = {}
# Dungeon ids that have been first-cleared (PRD #53 / issue #67). Mirrors
# MetaProgressionTracker.cleared_dungeons so the first-clear Gem bonus pays
# exactly once per dungeon across reloads. Stored as plain Array of strings
# so JSON round-trips cleanly. Legacy saves default to an empty array.
var cleared_dungeons: Array = []
# XP earned while offline since the last server sync. The sync orchestrator
# (post-#14) hands this to OfflineProgressMerger.merge_xp so the server
# record catches up to the offline gameplay without losing in-flight XP.
# Resets to 0 on a successful merge. Defaults to 0 so legacy saves
# round-trip cleanly.
var offline_xp_earned: int = 0
# Permanently owned cosmetic pack ids (non-consumable IAPs from #29). Stored as
# plain Array of strings so JSON round-trips cleanly via Variant. Legacy saves
# predating this field default to an empty array.
var cosmetic_packs: Array = []
# Paid class-unlock ids (PRD #26 Tier 3). Lowercase class id strings; consulted
# by UnlockRegistry.is_unlocked as an OR'd path alongside the gameplay gates so
# a paid unlock bypasses the meta-progression threshold without removing the
# earnable path. Legacy saves predating this field default to an empty array.
var paid_class_unlocks: Array = []
# Snapshot of the active solo dungeon run (PRD #42 / #46). Captures the seed
# (so DungeonGenerator regenerates the same graph), the current_room_id, and
# the explicitly cleared room ids. Empty dict when no run is in flight or
# when the player is in multiplayer (multiplayer runs aren't persisted —
# see QuitDungeonHandler). Legacy saves predating this field round-trip as
# an empty dict, which main_scene treats as "start a fresh dungeon."
var dungeon_run_state: Dictionary = {}
# Dual-currency balances (PRD #53 / issue #63). Default 0 so legacy saves
# round-trip cleanly. Sourced from a CurrencyLedger at save time and used
# to rehydrate one via to_currency_ledger() at load time.
var gold_balance: int = 0
var gem_balance: int = 0
# Last calendar date (ISO yyyy-mm-dd) on which the daily-login Gem bonus
# (PRD #53 / issue #68) was awarded. Empty string means the player has
# never received one — DailyLoginBonus.try_award treats that as a brand-new
# day and pays the first bonus. Stored on KittenSaveData (not on the
# tracker) because it's a per-save anchor, not a meta-progression milestone.
var last_login_date: String = ""

static func from_character(c: CharacterData, tree: SkillTree = null, tracker: MetaProgressionTracker = null, xp_tracker: OfflineXPTracker = null, cosmetic_inventory: CosmeticInventory = null, paid_unlocks: PaidUnlockInventory = null, dungeon_run_state: Dictionary = {}, currency_ledger: CurrencyLedger = null) -> KittenSaveData:
	var s := KittenSaveData.new()
	s.character_name = c.character_name
	s.character_class = int(c.character_class)
	s.appearance_index = c.appearance_index
	s.level = c.level
	s.xp = c.xp
	s.hp = c.hp
	s.max_hp = c.max_hp
	s.attack = c.attack
	s.defense = c.defense
	s.speed = c.speed
	s.skill_points = c.skill_points
	s.magic_attack = c.magic_attack
	s.magic_points = c.magic_points
	s.max_mp = c.max_mp
	s.magic_resistance = c.magic_resistance
	s.dexterity = c.dexterity
	s.evasion = c.evasion
	s.crit_chance = c.crit_chance
	s.luck = c.luck
	s.regeneration = c.regeneration
	if tree != null:
		s.unlocked_skill_ids = tree.unlocked_ids()
	if tracker != null:
		s.dungeons_completed = tracker.dungeons_completed
		s.max_level_per_class = tracker.max_level_per_class.duplicate()
		s.cleared_dungeons = tracker.cleared_dungeons.duplicate()
	if xp_tracker != null:
		s.offline_xp_earned = xp_tracker.pending_xp
	if cosmetic_inventory != null:
		s.cosmetic_packs = cosmetic_inventory.owned_pack_ids.duplicate()
	if paid_unlocks != null:
		s.paid_class_unlocks = paid_unlocks.owned_class_ids.duplicate()
	s.dungeon_run_state = dungeon_run_state.duplicate(true)
	if currency_ledger != null:
		s.gold_balance = currency_ledger.balance(CurrencyLedger.Currency.GOLD)
		s.gem_balance = currency_ledger.balance(CurrencyLedger.Currency.GEM)
	return s

func apply_to(c: CharacterData) -> void:
	c.character_name = character_name
	c.character_class = character_class
	c.appearance_index = appearance_index
	c.level = level
	c.xp = xp
	c.hp = hp
	c.max_hp = max_hp
	c.attack = attack
	c.defense = defense
	c.speed = speed
	c.skill_points = skill_points
	c.magic_attack = magic_attack
	c.magic_points = magic_points
	c.max_mp = max_mp
	c.magic_resistance = magic_resistance
	c.dexterity = dexterity
	c.evasion = evasion
	c.crit_chance = crit_chance
	c.luck = luck
	c.regeneration = regeneration

func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"character_class": character_class,
		"appearance_index": appearance_index,
		"level": level,
		"xp": xp,
		"hp": hp,
		"max_hp": max_hp,
		"attack": attack,
		"defense": defense,
		"speed": speed,
		"skill_points": skill_points,
		"magic_attack": magic_attack,
		"magic_points": magic_points,
		"max_mp": max_mp,
		"magic_resistance": magic_resistance,
		"dexterity": dexterity,
		"evasion": evasion,
		"crit_chance": crit_chance,
		"luck": luck,
		"regeneration": regeneration,
		"unlocked_skill_ids": unlocked_skill_ids,
		"dungeons_completed": dungeons_completed,
		"max_level_per_class": max_level_per_class,
		"cleared_dungeons": cleared_dungeons,
		"offline_xp_earned": offline_xp_earned,
		"cosmetic_packs": cosmetic_packs,
		"paid_class_unlocks": paid_class_unlocks,
		"dungeon_run_state": dungeon_run_state,
		"gold_balance": gold_balance,
		"gem_balance": gem_balance,
		"last_login_date": last_login_date,
	}

static func from_dict(d: Dictionary) -> KittenSaveData:
	var s := KittenSaveData.new()
	s.character_name = String(d.get("character_name", "Kitten"))
	s.character_class = int(d.get("character_class", 0))
	s.appearance_index = int(d.get("appearance_index", 0))
	s.level = int(d.get("level", 1))
	s.xp = int(d.get("xp", 0))
	s.hp = int(d.get("hp", 0))
	s.max_hp = int(d.get("max_hp", 0))
	s.attack = int(d.get("attack", 0))
	s.defense = int(d.get("defense", 0))
	s.speed = float(d.get("speed", 0.0))
	s.skill_points = int(d.get("skill_points", 0))
	s.magic_attack = int(d.get("magic_attack", 0))
	s.magic_points = int(d.get("magic_points", 0))
	s.max_mp = int(d.get("max_mp", 0))
	s.magic_resistance = int(d.get("magic_resistance", 0))
	s.dexterity = int(d.get("dexterity", 0))
	s.evasion = float(d.get("evasion", 0.0))
	s.crit_chance = float(d.get("crit_chance", 0.0))
	s.luck = int(d.get("luck", 0))
	s.regeneration = int(d.get("regeneration", 0))
	var ids = d.get("unlocked_skill_ids", [])
	if ids is Array:
		s.unlocked_skill_ids = ids.duplicate()
	s.dungeons_completed = int(d.get("dungeons_completed", 0))
	var per_class = d.get("max_level_per_class", {})
	if per_class is Dictionary:
		for k in per_class.keys():
			s.max_level_per_class[String(k).to_lower()] = int(per_class[k])
	var cleared = d.get("cleared_dungeons", [])
	if cleared is Array:
		for raw in cleared:
			var id := String(raw)
			if id != "" and not s.cleared_dungeons.has(id):
				s.cleared_dungeons.append(id)
	s.offline_xp_earned = int(d.get("offline_xp_earned", 0))
	var packs = d.get("cosmetic_packs", [])
	if packs is Array:
		s.cosmetic_packs = packs.duplicate()
	var unlocks = d.get("paid_class_unlocks", [])
	if unlocks is Array:
		for raw in unlocks:
			var key := String(raw).to_lower()
			if key != "" and not s.paid_class_unlocks.has(key):
				s.paid_class_unlocks.append(key)
	var run_state = d.get("dungeon_run_state", {})
	if run_state is Dictionary:
		s.dungeon_run_state = run_state.duplicate(true)
	s.gold_balance = int(d.get("gold_balance", 0))
	s.gem_balance = int(d.get("gem_balance", 0))
	s.last_login_date = String(d.get("last_login_date", ""))
	return s

func to_tracker() -> MetaProgressionTracker:
	var t := MetaProgressionTracker.new()
	t.dungeons_completed = dungeons_completed
	t.max_level_per_class = max_level_per_class.duplicate()
	for id in cleared_dungeons:
		var s_id := String(id)
		if s_id != "" and not t.cleared_dungeons.has(s_id):
			t.cleared_dungeons.append(s_id)
	return t

func to_offline_xp_tracker() -> OfflineXPTracker:
	var t := OfflineXPTracker.new()
	t.pending_xp = offline_xp_earned
	return t

func to_cosmetic_inventory() -> CosmeticInventory:
	var inv := CosmeticInventory.new()
	inv.owned_pack_ids = cosmetic_packs.duplicate()
	return inv

func to_paid_unlock_inventory() -> PaidUnlockInventory:
	var inv := PaidUnlockInventory.new()
	inv.owned_class_ids = paid_class_unlocks.duplicate()
	return inv

func to_currency_ledger() -> CurrencyLedger:
	var ledger := CurrencyLedger.new()
	if gold_balance > 0:
		ledger.credit(gold_balance, CurrencyLedger.Currency.GOLD)
	if gem_balance > 0:
		ledger.credit(gem_balance, CurrencyLedger.Currency.GEM)
	return ledger
