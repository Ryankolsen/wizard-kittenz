class_name CharacterSlotData
extends RefCounted

# Per-character save fields — one per occupied slot in the SaveBundle. Carved
# out of the legacy KittenSaveData per PRD #250 so each archetype slot holds
# its own class/level/stats/skills/quickbar/items/in-flight-run independently.

var character_name: String = "Kitten"
var character_class: int = 0
var appearance_index: int = 0
var level: int = 1
var xp: int = 0
var hp: int = 0
var max_hp: int = 0
var attack: int = 0
var defense: int = 0
var speed: float = 0.0
var skill_points: int = 0
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
# Per-stat allocated SP investment + schema version (PRD #316 / issue #319).
# schema_version drives the one-time respec on first load: legacy slots omit
# the field and default to 0, which SkillPointRespec.migrate detects.
var allocated_points: Dictionary = {}
var schema_version: int = 0
var unlocked_skill_ids: Array = []
var equipped_items: Dictionary = {}
var item_bag: Array = []
var quickbar_slots: Array = []
var dungeon_run_state: Dictionary = {}
var offline_xp_earned: int = 0

# Snapshot live per-character state into a slot. Used by SaveManager.save_from_state
# to assemble the active slot of the SaveBundle (PRD #250 / slice 2). Each
# arg is optional so callers writing a minimal slot (character_creation's
# initial save) don't have to thread null placeholders.
static func from_state(c: CharacterData, tree: SkillTree = null, item_inv: ItemInventory = null, qb: Quickbar = null, run_state: Dictionary = {}, xp_tracker: OfflineXPTracker = null) -> CharacterSlotData:
	var s := CharacterSlotData.new()
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
	s.mp_regen = c.mp_regen
	s.allocated_points = c.allocated_points.duplicate()
	s.schema_version = c.schema_version
	if tree != null:
		s.unlocked_skill_ids = tree.unlocked_ids()
	if item_inv != null:
		for slot_kind in [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.ACCESSORY]:
			var eq: ItemData = item_inv.equipped_in(slot_kind)
			if eq != null:
				s.equipped_items[int(slot_kind)] = eq.id
		for it in item_inv.bag_items():
			s.item_bag.append(it.id)
	if qb != null:
		s.quickbar_slots = qb.serialize().get("slots", [])
	s.dungeon_run_state = run_state.duplicate(true)
	if xp_tracker != null:
		s.offline_xp_earned = xp_tracker.pending_xp
	return s

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
		"mp_regen": mp_regen,
		"allocated_points": allocated_points.duplicate(),
		"schema_version": schema_version,
		"unlocked_skill_ids": unlocked_skill_ids.duplicate(),
		"equipped_items": equipped_items.duplicate(),
		"item_bag": item_bag.duplicate(),
		"quickbar_slots": quickbar_slots.duplicate(),
		"dungeon_run_state": dungeon_run_state.duplicate(true),
		"offline_xp_earned": offline_xp_earned,
	}

static func from_dict(d: Dictionary) -> CharacterSlotData:
	var s := CharacterSlotData.new()
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
	s.mp_regen = float(d.get("mp_regen", 0.0))
	var allocs = d.get("allocated_points", {})
	if allocs is Dictionary:
		for k in allocs.keys():
			s.allocated_points[String(k)] = int(allocs[k])
	s.schema_version = int(d.get("schema_version", 0))
	var ids = d.get("unlocked_skill_ids", [])
	if ids is Array:
		s.unlocked_skill_ids = ids.duplicate()
	var eq = d.get("equipped_items", {})
	if eq is Dictionary:
		for k in eq.keys():
			s.equipped_items[int(k)] = String(eq[k])
	var bag = d.get("item_bag", [])
	if bag is Array:
		for raw in bag:
			s.item_bag.append(String(raw))
	var qb = d.get("quickbar_slots", [])
	if qb is Array:
		s.quickbar_slots = qb.duplicate()
	var run_state = d.get("dungeon_run_state", {})
	if run_state is Dictionary:
		s.dungeon_run_state = run_state.duplicate(true)
	s.offline_xp_earned = int(d.get("offline_xp_earned", 0))
	return s
