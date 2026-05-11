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
# Stored as plain Array (not PackedStringArray) so JSON.stringify round-trips
# cleanly via Variant. Snapshot of SkillTree.unlocked_ids() at save time.
var unlocked_skill_ids: Array = []
# Meta-progression snapshot — the tracker's state at save time. Persisted
# alongside the kitten so unlock progress (dungeons cleared, max-level-per-
# class) survives across sessions. Stored as plain primitives so JSON
# round-trips cleanly.
var dungeons_completed: int = 0
var max_level_per_class: Dictionary = {}
# XP earned while offline since the last server sync. The sync orchestrator
# (post-#14) hands this to OfflineProgressMerger.merge_xp so the server
# record catches up to the offline gameplay without losing in-flight XP.
# Resets to 0 on a successful merge. Defaults to 0 so legacy saves
# round-trip cleanly.
var offline_xp_earned: int = 0

static func from_character(c: CharacterData, tree: SkillTree = null, tracker: MetaProgressionTracker = null, xp_tracker: OfflineXPTracker = null) -> KittenSaveData:
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
	if tree != null:
		s.unlocked_skill_ids = tree.unlocked_ids()
	if tracker != null:
		s.dungeons_completed = tracker.dungeons_completed
		s.max_level_per_class = tracker.max_level_per_class.duplicate()
	if xp_tracker != null:
		s.offline_xp_earned = xp_tracker.pending_xp
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
		"unlocked_skill_ids": unlocked_skill_ids,
		"dungeons_completed": dungeons_completed,
		"max_level_per_class": max_level_per_class,
		"offline_xp_earned": offline_xp_earned,
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
	var ids = d.get("unlocked_skill_ids", [])
	if ids is Array:
		s.unlocked_skill_ids = ids.duplicate()
	s.dungeons_completed = int(d.get("dungeons_completed", 0))
	var per_class = d.get("max_level_per_class", {})
	if per_class is Dictionary:
		for k in per_class.keys():
			s.max_level_per_class[String(k).to_lower()] = int(per_class[k])
	s.offline_xp_earned = int(d.get("offline_xp_earned", 0))
	return s

func to_tracker() -> MetaProgressionTracker:
	var t := MetaProgressionTracker.new()
	t.dungeons_completed = dungeons_completed
	t.max_level_per_class = max_level_per_class.duplicate()
	return t

func to_offline_xp_tracker() -> OfflineXPTracker:
	var t := OfflineXPTracker.new()
	t.pending_xp = offline_xp_earned
	return t
