class_name EnemyData
extends Resource

# PRD #297 adds 9 boss-only kinds to the tail of the enum (slice 1 / #298).
# They have no defaults beyond what the static helpers below already return for
# any kind not explicitly cased — slice 2 / #299 wires per-kind stats and
# display names. Order is the canonical floor order from BossRoster.
enum EnemyKind {
	ANGRY_PIGEON,
	ROGUE_ROOMBA,
	DOG_KNIGHT,
	CATNIP_DEALER,
	HAUNTED_SPRAY_BOTTLE,
	SIR_PICKLETON,
	OLD_LADY_PEARL,
	TRASH_PANDA_TYRONE,
	BIG_BRUISER_BUSTER,
	LAST_CALL_LARRY,
	THE_BOUNCER,
	DJ_DUBSTEP,
	KARAOKE_KAREN,
	WARDEN_WRETCHED,
}

@export var enemy_name: String = "Angry Pigeon"
@export var kind: EnemyKind = EnemyKind.ANGRY_PIGEON
@export var hp: int = 8
@export var max_hp: int = 8
@export var attack: int = 2
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
# Mob level (PRD #376 / issue #377). Standard mobs get this stamped by
# RoomSpawnPlanner via EnemyLevel.compute_level(kind, floor); display-only
# this slice — later slices route stat scaling through it. Defaults to 1
# so pre-#377 fixtures and tests that mint EnemyData directly still get a
# sensible Lv N readout instead of "Lv 0".
@export var level: int = 1
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
# Boss-only sprite paths sourced from BossRoster (PRD #297, slice #301).
# Empty for non-boss spawns and for legacy / test fixtures whose planner
# predates the field — Enemy.gd falls back to vacuum_boss in that case.
@export var boss_sprite_left_path: String = ""
@export var boss_sprite_right_path: String = ""
# Last move direction. Read by ThiefAbilities.backstab to detect attacks from
# behind (attacker.facing roughly aligned with target.facing).
var facing: Vector2 = Vector2.DOWN
# TAUNT spell state (PRD #124 / issue #128). When non-null, the AI should
# treat taunt_target as the focused target instead of the nearest player; the
# effect decays via tick_taunt(dt) each physics frame and clears once
# taunt_remaining reaches 0. Pure-data — Enemy node code reads these to
# override _find_player().
var detection_radius: float = EnemyAIState.DETECTION_RADIUS
# World-space Rect2 bounding this enemy's room. Non-zero only for the boss —
# set by RoomSpawnPlanner so Enemy._clamp_to_room_bounds() can keep the boss
# inside its room each physics frame.
var room_bounds: Rect2 = Rect2()
var taunt_target = null
var taunt_remaining: float = 0.0
# Cross-client identity for the TAUNT caster. Stamped by SpellEffectResolver
# alongside taunt_target when the resolver call site supplies caster_id (the
# casting player's Nakama id, same id XPBroadcaster registers). The local
# Enemy node's _select_taunt_target still matches by CharacterData reference
# (single source of truth on the casting client); this field is the seam the
# future RemoteTauntApplier reads on the receiving client where the caster's
# CharacterData object doesn't exist. Empty string means "no cross-client
# identity recorded" — solo / pre-handshake / unkeyed-test paths leave it
# unset, and tick_taunt clears it on expiry alongside taunt_target.
var taunt_source_id: String = ""

# Per-kind floor-1 stat profiles (PRD #376 / issue #378). Replaces the
# uniform 8/2 baseline so each kind has a role: Pigeon glass-cannon swarmer,
# Roomba erratic skirmisher, Catnip medium all-rounder, Spray fragile ranged
# poke, Dog Knight tank. Boss-tier kinds (Sir Pickleton onward) keep the
# legacy 8/2 baseline since BossScaling multiplies on top and per-boss
# differentiation is sprite/AI-driven.
static func base_max_hp_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.ANGRY_PIGEON: return 6
		EnemyKind.ROGUE_ROOMBA: return 12
		EnemyKind.CATNIP_DEALER: return 14
		EnemyKind.HAUNTED_SPRAY_BOTTLE: return 10
		EnemyKind.DOG_KNIGHT: return 24
	return 8

static func base_attack_for(k: EnemyKind) -> int:
	match k:
		EnemyKind.ANGRY_PIGEON: return 2
		EnemyKind.ROGUE_ROOMBA: return 3
		EnemyKind.CATNIP_DEALER: return 3
		EnemyKind.HAUNTED_SPRAY_BOTTLE: return 4
		EnemyKind.DOG_KNIGHT: return 4
	return 2

static func base_defense_for(k: EnemyKind) -> int:
	# Dog Knight (issue #163) remains the only standard kind with nonzero
	# defense — its raised armor is the gameplay reason to drop the mead
	# bottle instead of front-line tanking.
	if k == EnemyKind.DOG_KNIGHT:
		return 2
	return 0

static func base_xp_for(_k: EnemyKind) -> int:
	return 15

static func base_gold_for(_k: EnemyKind) -> int:
	return 2

static func display_name_for(k: EnemyKind) -> String:
	match k:
		EnemyKind.ANGRY_PIGEON: return "Angry Pigeon"
		EnemyKind.ROGUE_ROOMBA: return "Rogue Roomba"
		EnemyKind.DOG_KNIGHT: return "Dog Knight"
		EnemyKind.CATNIP_DEALER: return "Catnip Dealer"
		EnemyKind.HAUNTED_SPRAY_BOTTLE: return "Haunted Spray Bottle"
		EnemyKind.SIR_PICKLETON: return "Sir Pickleton"
		EnemyKind.OLD_LADY_PEARL: return "Old Lady Pearl"
		EnemyKind.TRASH_PANDA_TYRONE: return "Trash Panda Tyrone"
		EnemyKind.BIG_BRUISER_BUSTER: return "Big Bruiser Buster"
		EnemyKind.LAST_CALL_LARRY: return "Last Call Larry"
		EnemyKind.THE_BOUNCER: return "The Bouncer"
		EnemyKind.DJ_DUBSTEP: return "DJ Dubstep"
		EnemyKind.KARAOKE_KAREN: return "Karaoke Karen"
		EnemyKind.WARDEN_WRETCHED: return "Warden Wretched"
	return "Enemy"

# Hard ceiling for any per-kind detection radius on the 480x270 viewport.
# Pinned to the viewport half-height (135) — at the ceiling a kind aggros right
# at the top/bottom screen edge but never from off-screen vertically, which is
# what issue #260 forbids. The horizontal half-width (240) is wider, so the band
# only matters on the vertical axis. Aggro hold uses a 1.5x leash
# (EnemyAIState.LEASH_MULTIPLIER); the hold can briefly reach past 135 into the
# corners, but onset still requires the player inside the radius.
const DETECTION_RADIUS_MAX_PX: float = 135.0

static func base_detection_radius_for(k: EnemyKind) -> float:
	match k:
		EnemyKind.ANGRY_PIGEON:    return 80.0  # aerial, moderate awareness
		EnemyKind.ROGUE_ROOMBA:    return 90.0  # bounces into range quickly
		EnemyKind.DOG_KNIGHT:      return 135.0 # aggressive charger, capped at viewport half-height
		EnemyKind.CATNIP_DEALER:   return 75.0  # skittish but short-sighted
		EnemyKind.HAUNTED_SPRAY_BOTTLE: return 75.0  # floaty, dim
	return EnemyAIState.DETECTION_RADIUS

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
	e.detection_radius = base_detection_radius_for(k)
	return e

func is_alive() -> bool:
	return hp > 0

func take_damage(amount: int) -> int:
	var dealt := mini(amount, hp)
	hp -= dealt
	return dealt

# Decay the active TAUNT timer and clear taunt_target when it expires. Called
# from the Enemy node each physics frame; pure-data so tests can drive it
# directly without a SceneTree.
func tick_taunt(dt: float) -> void:
	if taunt_remaining <= 0.0:
		return
	taunt_remaining = maxf(0.0, taunt_remaining - dt)
	if taunt_remaining <= 0.0:
		taunt_target = null
		taunt_source_id = ""

func is_taunted() -> bool:
	# Taunt is "active" while the timer is still ticking AND we know who to
	# redirect to. Local-cast clients stamp taunt_target (CharacterData ref);
	# receiving co-op clients only know the caster's network player_id via
	# taunt_source_id (the caster's CharacterData object doesn't exist on the
	# remote side). Either identity hook is enough to gate AI redirect — the
	# Enemy node picks the resolver path that matches what's present.
	if taunt_remaining <= 0.0:
		return false
	return taunt_target != null or taunt_source_id != ""
