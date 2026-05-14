class_name EnemyData
extends Resource

enum EnemyKind { SLIME, BAT, RAT }

@export var enemy_name: String = "Slime"
@export var kind: EnemyKind = EnemyKind.SLIME
@export var hp: int = 4
@export var max_hp: int = 4
@export var attack: int = 1
@export var defense: int = 0
@export var xp_reward: int = 2
# Gold dropped on death (PRD #53). Credited to the local CurrencyLedger via
# KillRewardRouter on every kill — solo and co-op both pay the full amount
# (Gold is per-character, not party-split like XP).
@export var gold_reward: int = 2
# Marks this enemy as the dungeon's boss. Defaults false so a generic spawn
# never accidentally registers as a boss; the dungeon spawner sets it true
# on the boss room's enemy.
@export var is_boss: bool = false
# Stable per-spawn identifier. Empty by default — pre-spawn-layer code paths
# (test fixtures, the static enemy in main.tscn) leave it unset. The future
# dungeon spawn layer mints a unique id (e.g. "r3_e0" for room 3 enemy 0)
# so the wire layer's enemy-died packet and the local kill detection can
# converge through EnemyStateSyncManager.apply_death(enemy_id) idempotently.
# KillRewardRouter skips the apply_death call when this is empty so legacy
# / test enemies don't poke the registry with an unkeyed entry.
@export var enemy_id: String = ""
# World-space position the spawn layer should instantiate this enemy at. Set by
# RoomSpawnPlanner.register_all_room_enemies from the DungeonLayout room center
# so every client computes the same coordinate from the synced dungeon seed.
# Vector2.ZERO is the "no position assigned" sentinel — pre-spawn-layer fixtures
# and the legacy single-enemy-in-main.tscn path leave it unset; the scene
# spawner falls back to the node's authored position in that case.
@export var spawn_position: Vector2 = Vector2.ZERO
# Last move direction. Read by ThiefAbilities.backstab to detect attacks from
# behind (attacker.facing roughly aligned with target.facing).
var facing: Vector2 = Vector2.DOWN

static func base_max_hp_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.SLIME: return 4
		EnemyKind.BAT: return 3
		EnemyKind.RAT: return 5
	return 4

static func base_attack_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.SLIME: return 1
		EnemyKind.BAT: return 1
		EnemyKind.RAT: return 2
	return 1

static func base_defense_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.SLIME: return 0
		EnemyKind.BAT: return 0
		EnemyKind.RAT: return 1
	return 0

static func base_xp_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.SLIME: return 2
		EnemyKind.BAT: return 2
		EnemyKind.RAT: return 3
	return 2

static func base_gold_for(k: EnemyKind) -> int:
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
	e.attack = base_attack_for(k)
	e.defense = base_defense_for(k)
	e.xp_reward = base_xp_for(k)
	e.gold_reward = base_gold_for(k)
	return e

func is_alive() -> bool:
	return hp > 0

func take_damage(amount: int) -> int:
	var dealt := mini(amount, hp)
	hp -= dealt
	return dealt
