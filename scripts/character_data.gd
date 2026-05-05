class_name CharacterData
extends Resource

enum CharacterClass { MAGE, THIEF, NINJA }

const SAVE_PATH := "user://character.tres"

@export var character_name: String = "Kitten"
@export var character_class: CharacterClass = CharacterClass.MAGE
@export var level: int = 1
@export var xp: int = 0
@export var hp: int = 10
@export var max_hp: int = 10
@export var attack: int = 2
@export var defense: int = 0
@export var skill_points: int = 0

static func base_max_hp_for(klass: CharacterClass, lvl: int) -> int:
	var base := 10
	match klass:
		CharacterClass.MAGE: base = 8
		CharacterClass.THIEF: base = 10
		CharacterClass.NINJA: base = 9
	return base + (lvl - 1) * 2

static func base_attack_for(klass: CharacterClass, _lvl: int) -> int:
	match klass:
		CharacterClass.MAGE: return 2
		CharacterClass.THIEF: return 3
		CharacterClass.NINJA: return 4
	return 2

static func base_defense_for(klass: CharacterClass, _lvl: int) -> int:
	match klass:
		CharacterClass.MAGE: return 0
		CharacterClass.THIEF: return 1
		CharacterClass.NINJA: return 0
	return 0

static func make_new(klass: CharacterClass, n: String = "Kitten") -> CharacterData:
	var c := CharacterData.new()
	c.character_name = n
	c.character_class = klass
	c.level = 1
	c.xp = 0
	var hp_max := base_max_hp_for(klass, 1)
	c.max_hp = hp_max
	c.hp = hp_max
	c.attack = base_attack_for(klass, 1)
	c.defense = base_defense_for(klass, 1)
	return c

func is_alive() -> bool:
	return hp > 0

func take_damage(amount: int) -> int:
	var dealt := mini(amount, hp)
	hp -= dealt
	return dealt

func heal(amount: int) -> int:
	var healed := mini(amount, max_hp - hp)
	hp += healed
	return healed

func save_to(path: String = SAVE_PATH) -> Error:
	return ResourceSaver.save(self, path)

static func load_from(path: String = SAVE_PATH) -> CharacterData:
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path)
	if loaded is CharacterData:
		return loaded
	return null
