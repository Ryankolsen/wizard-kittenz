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
var unlocked_skill_ids: Array = []
var equipped_items: Dictionary = {}
var item_bag: Array = []
var quickbar_slots: Array = []
var dungeon_run_state: Dictionary = {}
var offline_xp_earned: int = 0

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
