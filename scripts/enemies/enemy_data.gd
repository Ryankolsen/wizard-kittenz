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
# Elite flag (PRD #376 / issue #380). Set true for the ~10% of standard mobs
# rolled elite at dungeon-generation time by RoomPopulationPlanner. Drives:
# the "skip downward party-level clamp" branch in StandardEnemyScaling, the
# 2.5× xp/gold reward bonus, and the gold "Lv N" label + tint in #381.
# Bosses are never elite — the boss path in plan_enemy leaves this false.
@export var is_elite: bool = false
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
# poke, Dog Knight tank.
#
# Boss-tier kinds (Sir Pickleton onward) gained their own profiles in PRD #518
# / issue #535, replacing the shared 8/2/0 baseline that made every boss the
# same numbers behind a different sprite. Each profile expresses that boss's
# two archetypes from the PRD's loadout table:
#
#   Sir Pickleton      7/4/0   ambush+charge   — assassin, hits hard, folds fast
#   Old Lady Pearl     6/2/0   summon+kite     — squishiest; the adds do the work
#   Trash Panda Tyrone 7/3/0   steal+zone      — evasive, survives by running
#   Big Bruiser Buster 14/4/0  slam+shove      — melee-denial wall, bulk is all HP
#   Last Call Larry    10/3/0  zone+enrage     — midweight; enrage is the spike
#   The Bouncer        12/3/1  shield+shove    — the only boss with any armor
#   DJ Dubstep         9/4/0   slam+enrage     — rhythm damage, no armor
#   Karaoke Karen      9/3/0   cone+summon     — pressures space, not trades
#   Warden Wretched    13/4/0  pull+zone       — tanky trapper
#
# These are pre-scaling values: BossScaling still multiplies on top of them
# (6x hp / 2.5x attack / 3x defense plus per-floor rates), so the spread here
# is deliberately narrow around the old baseline of 8.
#
# Issue #568 collapsed the five per-stat `match` statements PRD #518 / #535
# left behind into this single table, one entry per kind holding all four
# stats together — the same `_..._BY_KIND` shape enemy.gd's _TEXTURE_BY_KIND
# already uses for sprite paths. A kind added to the enum but not registered
# here now fails loudly for every stat at once instead of silently falling
# through four independent match statements out of step with each other.
# Dog Knight (issue #163) remains the only standard kind with nonzero
# defense — its raised armor is the gameplay reason to drop the mead bottle
# instead of front-line tanking.
#
# Boss base defense is deliberately tiny, and every boss but The Bouncer
# declares an explicit 0 (PRD #518 / issue #535). Two constraints squeeze it:
# DamageResolver subtracts defense from every hit with only a floor of 1, and
# BossScaling triples boss defense before per-floor scaling — so a boss at
# base 2 already blunts harder on floor 1 than the Dog Knight does, and the
# Dog Knight must stay the armored outlier of the whole enum (issue #163).
# The Bouncer's 1 becomes an effective 3 once scaled, which is what makes
# armor his identity; his shielded-front archetype (#542) carries the rest.
# The other bosses express their bulk through HP, not through mitigation, so
# a fight never becomes a chip-damage slog.
const _PROFILE_BY_KIND := {
	EnemyKind.ANGRY_PIGEON:         {"max_hp": 6,  "attack": 2, "defense": 0, "detection_radius": 80.0},
	EnemyKind.ROGUE_ROOMBA:         {"max_hp": 12, "attack": 3, "defense": 0, "detection_radius": 90.0},
	EnemyKind.DOG_KNIGHT:           {"max_hp": 24, "attack": 4, "defense": 2, "detection_radius": 135.0},
	EnemyKind.CATNIP_DEALER:        {"max_hp": 14, "attack": 3, "defense": 0, "detection_radius": 75.0},
	EnemyKind.HAUNTED_SPRAY_BOTTLE: {"max_hp": 10, "attack": 4, "defense": 0, "detection_radius": 75.0},
	# Boss radii track the PRD #518 loadouts: bosses that fight at range or
	# reach out (retreat-and-fire, pull, cone spray, steal) open at or near
	# the ceiling, while brawlers who want you in melee see less and hold
	# their ground. All stay <= DETECTION_RADIUS_MAX_PX so none aggros from
	# off-screen.
	EnemyKind.SIR_PICKLETON:        {"max_hp": 7,  "attack": 4, "defense": 0, "detection_radius": 120.0}, # stalks to reach your blind side
	EnemyKind.OLD_LADY_PEARL:       {"max_hp": 6,  "attack": 2, "defense": 0, "detection_radius": 135.0}, # opens fire at max range
	EnemyKind.TRASH_PANDA_TYRONE:   {"max_hp": 7,  "attack": 3, "defense": 0, "detection_radius": 130.0}, # spots the gold early
	EnemyKind.BIG_BRUISER_BUSTER:   {"max_hp": 14, "attack": 4, "defense": 0, "detection_radius": 90.0},  # slow brawler, waits for you
	EnemyKind.LAST_CALL_LARRY:      {"max_hp": 10, "attack": 3, "defense": 0, "detection_radius": 100.0}, # zoner, works the near floor
	EnemyKind.THE_BOUNCER:          {"max_hp": 12, "attack": 3, "defense": 1, "detection_radius": 95.0},  # holds the door, short leash
	EnemyKind.DJ_DUBSTEP:           {"max_hp": 9,  "attack": 4, "defense": 0, "detection_radius": 110.0}, # slam rings need some runway
	EnemyKind.KARAOKE_KAREN:        {"max_hp": 9,  "attack": 3, "defense": 0, "detection_radius": 125.0}, # lines up the cone from afar
	EnemyKind.WARDEN_WRETCHED:      {"max_hp": 13, "attack": 4, "defense": 0, "detection_radius": 135.0}, # the pull needs the longest reach
}

# The single fallback decision for any kind absent from _PROFILE_BY_KIND —
# every stat resolves through this one profile together, rather than four
# independent per-stat defaults that could silently drift out of step with
# each other (the failure mode issue #568 closes). Mirrors the pre-#535
# uniform baseline every kind shared before boss profiles existed.
const _FALLBACK_PROFILE := {"max_hp": 8, "attack": 2, "defense": 0, "detection_radius": EnemyAIState.DETECTION_RADIUS}

static func _profile_for(k) -> Dictionary:
	return _PROFILE_BY_KIND.get(k, _FALLBACK_PROFILE)

static func base_max_hp_for(k: EnemyKind) -> int:
	return _profile_for(k).max_hp

static func base_attack_for(k: EnemyKind) -> int:
	return _profile_for(k).attack

static func base_defense_for(k: EnemyKind) -> int:
	return _profile_for(k).defense

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
	return _profile_for(k).detection_radius

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

# Debuff/DOT status-effect tracker (PRD #418 / issue #421). Deliberately a
# pure-data module isolated from Spell/SpellEffectResolver — later issues
# (#426 DOT, #427 DEBUFF) wire spell casts into apply_dot/apply_debuff, but
# this file has no knowledge of either. Mirrors CharacterData's tick-based
# buff/regen shapes: DOT ticks damage once per accumulated second (same
# cadence as CharacterData.BUFF_GROUP_REGEN's heal-over-time), and debuffs
# apply a flat stat delta immediately and revert it on expiry (same shape as
# CharacterData.add_buff). Both are tickable in sub-duration increments,
# matching how tick_taunt(dt) is already called every physics frame.
var _dots: Array = []
var _debuffs: Array = []

func apply_dot(amount_per_tick: int, duration: float) -> void:
	if amount_per_tick <= 0 or duration <= 0.0:
		return
	_dots.append({"amount": amount_per_tick, "remaining": duration, "accum": 0.0})

func tick_dots(dt: float) -> int:
	if dt <= 0.0 or _dots.is_empty():
		return 0
	var total_dealt := 0
	var expired: Array = []
	for d in _dots:
		# Effective delta is clamped to remaining seconds so a single large dt
		# can't tick damage past the DOT's own duration.
		var eff: float = minf(dt, d.remaining)
		d.accum += eff
		while d.accum >= 1.0:
			d.accum -= 1.0
			if is_alive():
				total_dealt += take_damage(int(d.amount))
		d.remaining -= dt
		if d.remaining <= 0.0:
			expired.append(d)
	for d in expired:
		_dots.erase(d)
	return total_dealt

func apply_debuff(stat: String, amount: int, duration: float) -> void:
	if stat == "" or duration <= 0.0:
		return
	for d in _debuffs:
		if d.stat == stat:
			d.remaining = duration
			return
	_debuffs.append({"stat": stat, "amount": amount, "remaining": duration})
	var cur: Variant = get(stat)
	if cur == null:
		return
	if cur is int:
		set(stat, cur - amount)
	else:
		set(stat, cur - float(amount))

func tick_debuffs(dt: float) -> void:
	if dt <= 0.0 or _debuffs.is_empty():
		return
	var expired: Array = []
	for d in _debuffs:
		d.remaining -= dt
		if d.remaining <= 0.0:
			expired.append(d)
	for d in expired:
		var cur: Variant = get(d.stat)
		if cur != null:
			if cur is int:
				set(d.stat, cur + int(d.amount))
			else:
				set(d.stat, cur + float(d.amount))
		_debuffs.erase(d)
