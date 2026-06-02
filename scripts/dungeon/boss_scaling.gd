class_name BossScaling
extends RefCounted

# Single source of truth for boss stat scaling (PRD #322 / issue #323). Owns the
# per-boss multipliers that turn a standard enemy's base stats into boss stats,
# and the per-floor scaling rates that make deeper-floor bosses progressively
# nastier. Extracted from RoomSpawnPlanner so #324 (party size) and #325
# (average level) can stack their own multipliers on top of the boss baseline
# without piling more scaling logic into the planner.
#
# BOSS_ATTACK_MULT drop from 4 → 2.5 is the slice-1 balance change: floor-1
# vacuum boss attack falls from 8 to 5, so a level-1 Battle Kitten (10 hp,
# 1 defense) survives ~3 hits instead of dying in 2.

const BOSS_HP_MULT: float = 6.0
const BOSS_ATTACK_MULT: float = 2.5
const BOSS_DEFENSE_MULT: float = 3.0
const BOSS_XP_MULT: float = 3.0
const BOSS_GOLD_MULT: float = 4.0

# Per-floor scaling. Each additional floor multiplies the boss's stats and
# rewards by (1 + RATE * (floor_number - 1)). Floor 1 is the baseline (1.0x).
# Same rates the planner used pre-extraction; non-boss floor scaling reads
# these too so the rates stay in one place.
const FLOOR_HP_SCALE_PER_LEVEL: float = 0.55
const FLOOR_ATTACK_SCALE_PER_LEVEL: float = 0.35
const FLOOR_DEFENSE_SCALE_PER_LEVEL: float = 0.15
const FLOOR_XP_SCALE_PER_LEVEL: float = 0.25
const FLOOR_GOLD_SCALE_PER_LEVEL: float = 0.20

# Party-size multipliers (PRD #322 / issue #324). Index by clamped party size
# (1..4); party_size 0 maps to 1 (solo) and >4 clamps to 4. HP and attack only
# — defense, XP, and gold are intentionally not party-scaled (the PRD's table).
const PARTY_HP_MULT: Array = [1.0, 1.4, 1.75, 2.0]
const PARTY_ATTACK_MULT: Array = [1.0, 1.1, 1.2, 1.3]

# Applies boss multipliers + per-floor scaling to a base-stat dictionary and
# returns the scaled dictionary. base_stats keys: hp, attack, defense, xp,
# gold (missing keys default to 0). floor_number < 1 is treated as floor 1
# (no negative scaling, defensive against stale callers).
#
# Defense scaling matches the planner's pre-extraction contract: a base
# defense of 0 stays at 0 across floors (no scaling from nothing). Bosses
# with nonzero base defense (Dog Knight) get the full curve.
static func compute_boss_stats(base_stats: Dictionary, floor_number: int, party_size: int = 1) -> Dictionary:
	var hp: float = float(int(base_stats.get("hp", 0)))
	var attack: float = float(int(base_stats.get("attack", 0)))
	var defense: float = float(int(base_stats.get("defense", 0)))
	var xp: float = float(int(base_stats.get("xp", 0)))
	var gold: float = float(int(base_stats.get("gold", 0)))

	hp *= BOSS_HP_MULT
	attack *= BOSS_ATTACK_MULT
	defense *= BOSS_DEFENSE_MULT
	xp *= BOSS_XP_MULT
	gold *= BOSS_GOLD_MULT

	var depth: int = maxi(0, floor_number - 1)
	if depth > 0:
		hp *= 1.0 + FLOOR_HP_SCALE_PER_LEVEL * float(depth)
		attack *= 1.0 + FLOOR_ATTACK_SCALE_PER_LEVEL * float(depth)
		if defense > 0.0:
			defense *= 1.0 + FLOOR_DEFENSE_SCALE_PER_LEVEL * float(depth)
		xp *= 1.0 + FLOOR_XP_SCALE_PER_LEVEL * float(depth)
		gold *= 1.0 + FLOOR_GOLD_SCALE_PER_LEVEL * float(depth)

	# Party scaling composes multiplicatively on top of floor scaling. Solo
	# (1) is the baseline 1.0×; only HP and attack scale — defense, XP, and
	# gold are intentionally unaffected so a 4-player run doesn't multiply
	# reward by party size on top of the per-kill split.
	var effective_party: int = party_size if party_size > 0 else 1
	var clamped_party: int = clampi(effective_party, 1, 4)
	hp *= float(PARTY_HP_MULT[clamped_party - 1])
	attack *= float(PARTY_ATTACK_MULT[clamped_party - 1])

	return {
		"hp": int(roundf(hp)),
		"attack": int(roundf(attack)),
		"defense": int(roundf(defense)),
		"xp": int(roundf(xp)),
		"gold": int(roundf(gold)),
	}
