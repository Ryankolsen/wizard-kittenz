class_name KittenSaveData
extends RefCounted

# Lightweight JSON-friendly projection of CharacterData. Lives separately from
# CharacterData so the save format can evolve without forcing scene/resource
# migrations. CharacterData is a Resource (.tres-shaped); save state is JSON.

var character_name: String = "Kitten"
var character_class: int = 0
var level: int = 1
var xp: int = 0
var hp: int = 0
var max_hp: int = 0
var attack: int = 0
var defense: int = 0

static func from_character(c: CharacterData) -> KittenSaveData:
	var s := KittenSaveData.new()
	s.character_name = c.character_name
	s.character_class = int(c.character_class)
	s.level = c.level
	s.xp = c.xp
	s.hp = c.hp
	s.max_hp = c.max_hp
	s.attack = c.attack
	s.defense = c.defense
	return s

func apply_to(c: CharacterData) -> void:
	c.character_name = character_name
	c.character_class = character_class
	c.level = level
	c.xp = xp
	c.hp = hp
	c.max_hp = max_hp
	c.attack = attack
	c.defense = defense

func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"character_class": character_class,
		"level": level,
		"xp": xp,
		"hp": hp,
		"max_hp": max_hp,
		"attack": attack,
		"defense": defense,
	}

static func from_dict(d: Dictionary) -> KittenSaveData:
	var s := KittenSaveData.new()
	s.character_name = String(d.get("character_name", "Kitten"))
	s.character_class = int(d.get("character_class", 0))
	s.level = int(d.get("level", 1))
	s.xp = int(d.get("xp", 0))
	s.hp = int(d.get("hp", 0))
	s.max_hp = int(d.get("max_hp", 0))
	s.attack = int(d.get("attack", 0))
	s.defense = int(d.get("defense", 0))
	return s
