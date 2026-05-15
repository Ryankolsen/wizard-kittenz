class_name CharacterData
extends Resource

enum CharacterClass {
	MAGE, THIEF, NINJA, ARCHMAGE, MASTER_THIEF, SHADOW_NINJA,
	BATTLE_KITTEN, WIZARD_KITTEN, SLEEPY_KITTEN, CHONK_KITTEN,
	BATTLE_CAT, WIZARD_CAT, SLEEPY_CAT, CHONK_CAT,
}

const SAVE_PATH := "user://character.tres"

@export var character_name: String = "Kitten"
@export var character_class: CharacterClass = CharacterClass.MAGE
@export var level: int = 1
@export var xp: int = 0
@export var hp: int = 10
@export var max_hp: int = 10
@export var attack: int = 2
@export var defense: int = 0
@export var speed: float = 60.0
@export var skill_points: int = 0
# Expanded stat set (PRD #52 / issue #55). All new fields default to 0 / 0.0
# so legacy saves loading via apply_to leave them at neutral baselines.
# evasion and crit_chance are stored as floats in [0.0, 1.0]; displayed as %.
@export var magic_attack: int = 0
@export var magic_points: int = 0
@export var max_mp: int = 0
@export var magic_resistance: int = 0
@export var dexterity: int = 0
@export var evasion: float = 0.0
@export var crit_chance: float = 0.0
@export var luck: int = 0
@export var regeneration: int = 0
# Index into the (future) kitten sprite sheet. Pure data today — no
# sprite swap is wired yet — but the persistence layer carries it so
# Customize-flow choices survive save/load.
@export var appearance_index: int = 0
# Last move direction. Drives backstab / facing-aware abilities. Not @export'd
# because it's purely runtime — saves/loads don't need to round-trip the
# moment-to-moment vector.
var facing: Vector2 = Vector2.DOWN

static func base_max_hp_for(klass: CharacterClass, lvl: int) -> int:
	var base := 10
	match klass:
		CharacterClass.MAGE: base = 8
		CharacterClass.THIEF: base = 10
		CharacterClass.NINJA: base = 9
		CharacterClass.ARCHMAGE: base = 12
		CharacterClass.MASTER_THIEF: base = 14
		CharacterClass.SHADOW_NINJA: base = 13
		CharacterClass.WIZARD_KITTEN: base = 8
		CharacterClass.BATTLE_KITTEN: base = 10
		CharacterClass.SLEEPY_KITTEN: base = 10
		CharacterClass.CHONK_KITTEN: base = 14
		CharacterClass.WIZARD_CAT: base = 10
		CharacterClass.BATTLE_CAT: base = 12
		CharacterClass.SLEEPY_CAT: base = 12
		CharacterClass.CHONK_CAT: base = 16
	return base + (lvl - 1) * 2

static func base_attack_for(klass: CharacterClass, _lvl: int) -> int:
	match klass:
		CharacterClass.MAGE: return 2
		CharacterClass.THIEF: return 3
		CharacterClass.NINJA: return 4
		CharacterClass.ARCHMAGE: return 4
		CharacterClass.MASTER_THIEF: return 5
		CharacterClass.SHADOW_NINJA: return 6
		CharacterClass.WIZARD_KITTEN: return 2
		CharacterClass.BATTLE_KITTEN: return 5
		CharacterClass.SLEEPY_KITTEN: return 2
		CharacterClass.CHONK_KITTEN: return 3
		CharacterClass.WIZARD_CAT: return 3
		CharacterClass.BATTLE_CAT: return 7
		CharacterClass.SLEEPY_CAT: return 3
		CharacterClass.CHONK_CAT: return 4
	return 2

static func base_defense_for(klass: CharacterClass, _lvl: int) -> int:
	match klass:
		CharacterClass.MAGE: return 0
		CharacterClass.THIEF: return 1
		CharacterClass.NINJA: return 0
		CharacterClass.ARCHMAGE: return 1
		CharacterClass.MASTER_THIEF: return 2
		CharacterClass.SHADOW_NINJA: return 1
		CharacterClass.WIZARD_KITTEN: return 0
		CharacterClass.BATTLE_KITTEN: return 1
		CharacterClass.SLEEPY_KITTEN: return 0
		CharacterClass.CHONK_KITTEN: return 3
		CharacterClass.WIZARD_CAT: return 1
		CharacterClass.BATTLE_CAT: return 2
		CharacterClass.SLEEPY_CAT: return 1
		CharacterClass.CHONK_CAT: return 4
	return 0

# Per-class movement speed (px/sec). Thief is fastest, Mage slowest, Ninja
# balanced — matches the issue's "high speed / balanced / low" archetype.
# Tier-2 classes (Archmage / Master Thief / Shadow Ninja) inherit their base
# class's identity (Master Thief stays fastest, Shadow Ninja balanced) with
# a small uplift across the board so the upgrade feels meaningful without
# warping the per-class archetype.
static func base_speed_for(klass: CharacterClass, _lvl: int) -> float:
	match klass:
		CharacterClass.MAGE: return 50.0
		CharacterClass.THIEF: return 75.0
		CharacterClass.NINJA: return 60.0
		CharacterClass.ARCHMAGE: return 55.0
		CharacterClass.MASTER_THIEF: return 80.0
		CharacterClass.SHADOW_NINJA: return 65.0
		CharacterClass.WIZARD_KITTEN: return 60.0
		CharacterClass.BATTLE_KITTEN: return 65.0
		CharacterClass.SLEEPY_KITTEN: return 50.0
		CharacterClass.CHONK_KITTEN: return 45.0
		CharacterClass.WIZARD_CAT: return 65.0
		CharacterClass.BATTLE_CAT: return 70.0
		CharacterClass.SLEEPY_CAT: return 55.0
		CharacterClass.CHONK_CAT: return 50.0
	return 60.0

static func base_magic_attack_for(klass: CharacterClass, _lvl: int) -> int:
	# Mages are magic-leaning; thieves are not. Mirrors base_attack_for shape.
	match klass:
		CharacterClass.MAGE: return 4
		CharacterClass.THIEF: return 1
		CharacterClass.NINJA: return 2
		CharacterClass.ARCHMAGE: return 6
		CharacterClass.MASTER_THIEF: return 2
		CharacterClass.SHADOW_NINJA: return 3
		CharacterClass.WIZARD_KITTEN: return 5
		CharacterClass.BATTLE_KITTEN: return 1
		CharacterClass.SLEEPY_KITTEN: return 3
		CharacterClass.CHONK_KITTEN: return 1
		CharacterClass.WIZARD_CAT: return 7
		CharacterClass.BATTLE_CAT: return 2
		CharacterClass.SLEEPY_CAT: return 4
		CharacterClass.CHONK_CAT: return 2
	return 2

static func base_max_mp_for(klass: CharacterClass, lvl: int) -> int:
	var base := 5
	match klass:
		CharacterClass.MAGE: base = 10
		CharacterClass.THIEF: base = 3
		CharacterClass.NINJA: base = 5
		CharacterClass.ARCHMAGE: base = 14
		CharacterClass.MASTER_THIEF: base = 4
		CharacterClass.SHADOW_NINJA: base = 7
		CharacterClass.WIZARD_KITTEN: base = 10
		CharacterClass.BATTLE_KITTEN: base = 4
		CharacterClass.SLEEPY_KITTEN: base = 10
		CharacterClass.CHONK_KITTEN: base = 4
		CharacterClass.WIZARD_CAT: base = 14
		CharacterClass.BATTLE_CAT: base = 6
		CharacterClass.SLEEPY_CAT: base = 14
		CharacterClass.CHONK_CAT: base = 6
	return base + (lvl - 1) * 2

static func base_regeneration_for(klass: CharacterClass, _lvl: int) -> int:
	match klass:
		CharacterClass.WIZARD_KITTEN: return 0
		CharacterClass.BATTLE_KITTEN: return 0
		CharacterClass.SLEEPY_KITTEN: return 3
		CharacterClass.CHONK_KITTEN: return 1
		CharacterClass.WIZARD_CAT: return 0
		CharacterClass.BATTLE_CAT: return 0
		CharacterClass.SLEEPY_CAT: return 4
		CharacterClass.CHONK_CAT: return 2
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
	c.speed = base_speed_for(klass, 1)
	c.magic_attack = base_magic_attack_for(klass, 1)
	var mp_max := base_max_mp_for(klass, 1)
	c.max_mp = mp_max
	c.magic_points = mp_max
	c.regeneration = base_regeneration_for(klass, 1)
	return c

func apply_stat_delta(stat_name: String, delta: float) -> void:
	if stat_name == "":
		return
	var cur: Variant = get(stat_name)
	if cur == null:
		return
	if cur is int:
		set(stat_name, cur + roundi(delta))
	else:
		set(stat_name, cur + delta)

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

func clone() -> CharacterData:
	var c := CharacterData.new()
	c.character_name = character_name
	c.character_class = character_class
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
	c.appearance_index = appearance_index
	c.facing = facing
	return c

func save_to(path: String = SAVE_PATH) -> Error:
	return ResourceSaver.save(self, path)

static func load_from(path: String = SAVE_PATH) -> CharacterData:
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path)
	if loaded is CharacterData:
		return loaded
	return null
