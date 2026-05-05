class_name EnemyData
extends Resource

enum EnemyKind { SLIME, BAT, RAT }

@export var enemy_name: String = "Slime"
@export var kind: EnemyKind = EnemyKind.SLIME
@export var hp: int = 4
@export var max_hp: int = 4
@export var damage: int = 1
@export var xp_reward: int = 2

static func base_max_hp_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.SLIME: return 4
		EnemyKind.BAT: return 3
		EnemyKind.RAT: return 5
	return 4

static func base_damage_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.SLIME: return 1
		EnemyKind.BAT: return 1
		EnemyKind.RAT: return 2
	return 1

static func base_xp_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.SLIME: return 2
		EnemyKind.BAT: return 2
		EnemyKind.RAT: return 3
	return 2

static func display_name_for(k: EnemyKind) -> String:
	match k:
		EnemyKind.SLIME: return "Slime"
		EnemyKind.BAT: return "Bat"
		EnemyKind.RAT: return "Rat"
	return "Enemy"

static func make_new(k: EnemyKind) -> EnemyData:
	var e := EnemyData.new()
	e.kind = k
	e.enemy_name = display_name_for(k)
	e.max_hp = base_max_hp_for(k)
	e.hp = e.max_hp
	e.damage = base_damage_for(k)
	e.xp_reward = base_xp_for(k)
	return e

func is_alive() -> bool:
	return hp > 0

func take_damage(amount: int) -> int:
	var dealt := mini(amount, hp)
	hp -= dealt
	return dealt
