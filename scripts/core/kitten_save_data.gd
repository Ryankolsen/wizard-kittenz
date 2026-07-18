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
# Lifetime XP counter, never decreasing across level-ups (issue #413/#414).
# Legacy saves predating this field default to 0.
var total_xp: int = 0
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
var mp_regen: float = 0.0
# Skill-point allocation snapshot + schema flag (PRD #316 / issue #319).
# allocated_points is the per-stat invest dict mirroring CharacterData;
# schema_version drives the one-time respec on first load post-tier (legacy
# saves omit the key and default to 0, which triggers SkillPointRespec.migrate).
var allocated_points: Dictionary = {}
var schema_version: int = 0
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
# Permanently owned skill ids (non-consumable purchases from #69). Lowercase
# skill id strings; consulted by the future SkillTree availability gate as an
# OR'd path alongside the earnable unlock condition. Legacy saves predating
# this field default to an empty array.
var skill_unlocks: Array = []
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
# Last calendar date (ISO yyyy-mm-dd) on which the daily-login streak was
# claimed (PRD #237 / issue #241). Empty string means the player has never
# claimed — DailyStreakEngine.resolve treats that as a first-ever login and
# starts a fresh streak at Day 1. Stored on KittenSaveData (not on the
# tracker) because it's a per-save anchor, not a meta-progression milestone.
var last_login_date: String = ""
# Daily-login streak position (PRD #237 / issue #239). 1–30 while a streak is
# active; 0 means "no streak yet" (new save) or "streak reset" — the engine
# advances this on a successful claim. Stored on KittenSaveData so it shares
# the per-save lifecycle with last_login_date. Legacy saves default to 0.
var streak_day: int = 0
# Items System (PRD #73 / issue #78). equipped_items maps slot int
# (ItemData.Slot) to item id string. item_bag is an array of item id strings.
# Both default to empty so legacy saves predating items round-trip cleanly
# without migration. Unknown ids at load time are silently skipped via
# ItemCatalog.find returning null.
var equipped_items: Dictionary = {}
var item_bag: Array = []
# Quickbar slot bindings (PRD #210 / slice 5). Length-4 array of spell ids;
# empty slots serialize as "". Default empty Array (not [", ", ", "]) marks a
# legacy save written before this field shipped — to_quickbar() walks the
# tree's unlocked spells to auto-fill in that case. Once the migration runs
# the next save writes the now-filled slots and never re-migrates.
var quickbar_slots: Array = []
# Potion persistence (PRD #358 / slice 6). consumable_inventory_data is the
# {potion_id: count} dict ConsumableInventory.serialize emits; potion_belt_slots
# is a length-3 array of potion ids ("" for empty). Both default empty so a
# save written before this slice round-trips cleanly.
var consumable_inventory_data: Dictionary = {}
var potion_belt_slots: Array = []
# Transient: tracks whether the source dict had the quickbar_slots key. Not
# serialized — `to_dict()` always emits the slots array. Set true by
# from_character (which is given a live Quickbar) and by from_dict when the
# key is present. False marks a legacy save so to_quickbar() runs migration.
var _quickbar_present_in_save: bool = false

static func from_character(c: CharacterData, tree: SkillTree = null, tracker: MetaProgressionTracker = null, xp_tracker: OfflineXPTracker = null, cosmetic_inventory: CosmeticInventory = null, paid_unlocks: PaidUnlockInventory = null, dungeon_run_state: Dictionary = {}, currency_ledger: CurrencyLedger = null, skill_inventory = null, item_inventory: ItemInventory = null, quickbar: Quickbar = null, streak_day: int = 0, last_login_date: String = "", consumable_inventory: ConsumableInventory = null, potion_belt: PotionBelt = null) -> KittenSaveData:
	var s := KittenSaveData.new()
	s.character_name = c.character_name
	s.character_class = int(c.character_class)
	s.appearance_index = c.appearance_index
	s.level = c.level
	s.xp = c.xp
	s.total_xp = c.total_xp
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
	s.mp_regen = c.mp_regen
	s.allocated_points = c.allocated_points.duplicate()
	s.schema_version = c.schema_version
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
	if skill_inventory != null:
		s.skill_unlocks = skill_inventory.owned_skill_ids.duplicate()
	if item_inventory != null:
		for slot in [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.ACCESSORY]:
			var eq: ItemData = item_inventory.equipped_in(slot)
			if eq != null:
				s.equipped_items[int(slot)] = eq.id
		for it in item_inventory.bag_items():
			s.item_bag.append(it.id)
	if quickbar != null:
		s.quickbar_slots = quickbar.serialize().get("slots", [])
		s._quickbar_present_in_save = true
	if consumable_inventory != null:
		s.consumable_inventory_data = consumable_inventory.serialize()
	if potion_belt != null:
		s.potion_belt_slots = potion_belt.serialize().get("slots", [])
	s.streak_day = streak_day
	s.last_login_date = last_login_date
	return s

func apply_to(c: CharacterData) -> void:
	c.character_name = character_name
	c.character_class = character_class
	c.appearance_index = appearance_index
	c.level = level
	c.xp = xp
	c.total_xp = total_xp
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
	c.mp_regen = mp_regen
	c.allocated_points = allocated_points.duplicate()
	c.schema_version = schema_version
	# PRD #316 / issue #319: run the one-time respec on load so pre-tier
	# saves refund their allocations before items are re-applied by the
	# caller. No-op on saves already at SkillPointRespec.CURRENT_VERSION.
	SkillPointRespec.migrate(c)

func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"character_class": character_class,
		"appearance_index": appearance_index,
		"level": level,
		"xp": xp,
		"total_xp": total_xp,
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
		"mp_regen": mp_regen,
		"allocated_points": allocated_points,
		"schema_version": schema_version,
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
		"streak_day": streak_day,
		"skill_unlocks": skill_unlocks,
		"equipped_items": equipped_items,
		"item_bag": item_bag,
		"quickbar_slots": quickbar_slots,
		"consumable_inventory_data": consumable_inventory_data,
		"potion_belt_slots": potion_belt_slots,
	}

static func from_dict(d: Dictionary) -> KittenSaveData:
	var s := KittenSaveData.new()
	s.character_name = String(d.get("character_name", "Kitten"))
	s.character_class = _migrate_character_class(int(d.get("character_class", 0)))
	s.appearance_index = int(d.get("appearance_index", 0))
	s.level = int(d.get("level", 1))
	s.xp = int(d.get("xp", 0))
	s.total_xp = int(d.get("total_xp", 0))
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
	s.mp_regen = float(d.get("mp_regen", 0.0))
	var allocs = d.get("allocated_points", {})
	if allocs is Dictionary:
		for k in allocs.keys():
			s.allocated_points[String(k)] = int(allocs[k])
	s.schema_version = int(d.get("schema_version", 0))
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
	s.streak_day = int(d.get("streak_day", 0))
	var skills = d.get("skill_unlocks", [])
	if skills is Array:
		for raw in skills:
			var key := String(raw).to_lower()
			if key != "" and not s.skill_unlocks.has(key):
				s.skill_unlocks.append(key)
	var eq_items = d.get("equipped_items", {})
	if eq_items is Dictionary:
		for slot_key in eq_items.keys():
			s.equipped_items[int(slot_key)] = String(eq_items[slot_key])
	var bag = d.get("item_bag", [])
	if bag is Array:
		for raw in bag:
			s.item_bag.append(String(raw))
	if d.has("quickbar_slots"):
		s._quickbar_present_in_save = true
		var slots = d.get("quickbar_slots", [])
		if slots is Array:
			s.quickbar_slots = slots.duplicate()
	var inv_data = d.get("consumable_inventory_data", {})
	if inv_data is Dictionary:
		s.consumable_inventory_data = inv_data.duplicate()
	var belt_slots = d.get("potion_belt_slots", [])
	if belt_slots is Array:
		s.potion_belt_slots = belt_slots.duplicate()
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

func to_skill_inventory():
	var SkillInventoryClass = load("res://scripts/progression/skill_inventory.gd")
	var inv = SkillInventoryClass.new()
	inv.owned_skill_ids = skill_unlocks.duplicate()
	return inv

func to_item_inventory() -> ItemInventory:
	var inv := ItemInventory.new()
	for slot_key in equipped_items.keys():
		var item := ItemCatalog.find(String(equipped_items[slot_key]))
		if item != null:
			inv.equip(item)
	for raw_id in item_bag:
		var item2 := ItemCatalog.find(String(raw_id))
		if item2 != null:
			inv.add_to_bag(item2)
	return inv

# Maps legacy CharacterClass enum ints (0-5: MAGE/THIEF/NINJA/ARCHMAGE/
# MASTER_THIEF/SHADOW_NINJA) to the closest Kitten-system archetype so saves
# written before PRD #117 load cleanly. New enum values (6-13) pass through.
# Unknown values fall back to BATTLE_KITTEN to match CharacterFactory's
# default and keep loads non-fatal.
static func _migrate_character_class(raw: int) -> int:
	match raw:
		0: return CharacterData.CharacterClass.WIZARD_KITTEN  # MAGE
		1: return CharacterData.CharacterClass.BATTLE_KITTEN  # THIEF
		2: return CharacterData.CharacterClass.BATTLE_KITTEN  # NINJA
		3: return CharacterData.CharacterClass.WIZARD_CAT     # ARCHMAGE
		4: return CharacterData.CharacterClass.BATTLE_CAT     # MASTER_THIEF
		5: return CharacterData.CharacterClass.BATTLE_CAT     # SHADOW_NINJA
	if raw >= int(CharacterData.CharacterClass.BATTLE_KITTEN) and raw <= int(CharacterData.CharacterClass.CHONK_CAT):
		return raw
	return CharacterData.CharacterClass.BATTLE_KITTEN

# Builds a Quickbar reflecting either the saved slot bindings or — on a legacy
# save that predates the quickbar field — an auto-filled bar derived from the
# tree's currently-unlocked spells in tree order. The migration path mirrors
# slice-2 Player bootstrap: walk get_unlocked_spells() and call
# on_spell_unlocked, which fills the lowest empty slot. Returned Quickbar is
# owned by the caller (GameState) and re-serialized by the next save, which
# pins the migrated state and prevents a re-run on subsequent loads.
func to_quickbar(tree: SkillTree) -> Quickbar:
	var qb := Quickbar.new()
	if _quickbar_present_in_save:
		qb.deserialize({"slots": quickbar_slots}, tree)
		return qb
	if tree != null:
		for spell in tree.get_unlocked_spells():
			qb.on_spell_unlocked(spell)
	return qb

# Backward-compatibility synthesis (PRD #250 / slice 2). The on-disk save
# format is now a SaveBundle, but legacy callers (Nakama sync, character
# creation, every test that calls SaveManager.load) still expect a flat
# KittenSaveData. Flatten the bundle by copying account fields + the active
# slot's character fields into a single KittenSaveData. With no active slot
# the returned save is account-only (character fields stay at defaults).
static func from_bundle(bundle: SaveBundle) -> KittenSaveData:
	var s := KittenSaveData.new()
	if bundle == null:
		return s
	var account := bundle.account
	if account != null:
		s.gold_balance = account.gold_balance
		s.gem_balance = account.gem_balance
		s.paid_class_unlocks = account.paid_class_unlocks.duplicate()
		s.cosmetic_packs = account.cosmetic_packs.duplicate()
		s.skill_unlocks = account.skill_unlocks.duplicate()
		s.max_level_per_class = account.max_level_per_class.duplicate()
		s.dungeons_completed = account.dungeons_completed
		s.cleared_dungeons = account.cleared_dungeons.duplicate()
		s.streak_day = account.streak_day
		s.last_login_date = account.last_login_date
	var slot: CharacterSlotData = bundle.get_slot(bundle.active_slot) if bundle.active_slot != "" else null
	if slot != null:
		s.character_name = slot.character_name
		s.character_class = slot.character_class
		s.appearance_index = slot.appearance_index
		s.level = slot.level
		s.xp = slot.xp
		s.total_xp = slot.total_xp
		s.hp = slot.hp
		s.max_hp = slot.max_hp
		s.attack = slot.attack
		s.defense = slot.defense
		s.speed = slot.speed
		s.skill_points = slot.skill_points
		s.magic_attack = slot.magic_attack
		s.magic_points = slot.magic_points
		s.max_mp = slot.max_mp
		s.magic_resistance = slot.magic_resistance
		s.dexterity = slot.dexterity
		s.evasion = slot.evasion
		s.crit_chance = slot.crit_chance
		s.luck = slot.luck
		s.regeneration = slot.regeneration
		s.mp_regen = slot.mp_regen
		s.allocated_points = slot.allocated_points.duplicate()
		s.schema_version = slot.schema_version
		s.unlocked_skill_ids = slot.unlocked_skill_ids.duplicate()
		s.equipped_items = slot.equipped_items.duplicate()
		s.item_bag = slot.item_bag.duplicate()
		s.dungeon_run_state = slot.dungeon_run_state.duplicate(true)
		s.offline_xp_earned = slot.offline_xp_earned
		s.quickbar_slots = slot.quickbar_slots.duplicate()
		s._quickbar_present_in_save = true
		s.consumable_inventory_data = slot.consumable_inventory_data.duplicate()
		s.potion_belt_slots = slot.potion_belt_slots.duplicate()
	return s

# Rebuilds a ConsumableInventory from the persisted counts. Unknown potion ids
# (no longer in PotionCatalog) are dropped defensively so a save written against
# an older catalog version doesn't ressurect ghost stacks the rest of the game
# has no way to interact with.
func to_consumable_inventory() -> ConsumableInventory:
	var inv := ConsumableInventory.new()
	for k in consumable_inventory_data.keys():
		var pid := String(k)
		if PotionCatalog.find(pid) == null:
			continue
		var amount := int(consumable_inventory_data[k])
		if amount > 0:
			inv.add(pid, amount)
	return inv

func to_potion_belt() -> PotionBelt:
	var belt := PotionBelt.new()
	belt.deserialize({"slots": potion_belt_slots})
	return belt

func to_currency_ledger() -> CurrencyLedger:
	var ledger := CurrencyLedger.new()
	if gold_balance > 0:
		ledger.credit(gold_balance, CurrencyLedger.Currency.GOLD)
	if gem_balance > 0:
		ledger.credit(gem_balance, CurrencyLedger.Currency.GEM)
	return ledger
