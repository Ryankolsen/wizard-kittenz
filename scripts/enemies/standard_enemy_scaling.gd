class_name StandardEnemyScaling
extends RefCounted

# Pure-function module that derives a standard mob's final stats from its
# per-kind floor-1 base profile (#378), its level (#377), the floor number,
# and party guardrails (PRD #376 / issue #379). Counterpart to BossScaling:
# bosses get a 6×/2.5×/3× multiplier on top of base, then floor + party +
# level mult; standard mobs skip the boss multiplier and just get the floor /
# party / level mult chain.
#
# Identity contract: floor_number == 1, party_size == 1, avg_party_level on
# baseline (or sentinel) returns the base stats unchanged so the per-kind
# floor-1 profiles from #378 are exactly what shows up in-game on floor 1
# solo. Deeper floors grow stats by a per-level rate keyed off the cohort's
# level delta from its floor-1 level — kind-agnostic because every kind's
# per-kind offset is constant across floors, so the delta is depth * step
# regardless of which kind we're scaling.
#
# Party guardrails reuse BossScaling's tables and clamp constants so a
# standard mob and a boss scale through the same multiplier curve for
# party size + avg-party-level. Only HP and attack scale with party size /
# level mult — defense, xp, gold are intentionally unaffected (same
# rationale as BossScaling: avoid double-dipping on rewards and on the
# Dog-Knight defense curve).

const HP_GROWTH_PER_LEVEL: float = 0.15
const ATTACK_GROWTH_PER_LEVEL: float = 0.10
const DEFENSE_GROWTH_PER_LEVEL: float = 0.05
const XP_GROWTH_PER_LEVEL: float = 0.10
const GOLD_GROWTH_PER_LEVEL: float = 0.08

# Elite reward multiplier (PRD #376 / issue #380). Elite mobs pay ~2.5× xp and
# gold of the same kind's non-elite reward. Applied after level growth so the
# floor curve still flows through; rewards still skip party-size / party-level
# mults, matching the standard mob contract (no double-dip on rewards).
const ELITE_REWARD_MULT: float = 2.5

# Lower bound for the party-level mult on the elite path (PRD #380). Elites
# skip the downward clamp — they're "never softer than honest 1.0×" — but keep
# the upward clamp (LEVEL_MULT_MAX) and the party-size mult so an overleveled
# party still feels them as a meaningful threat.
const ELITE_LEVEL_MULT_MIN: float = 1.0

static func compute_standard_stats(base_stats: Dictionary, level: int, floor_number: int, party_size: int = 1, avg_party_level: float = -1.0, floor_baseline_level: int = -1, is_elite: bool = false) -> Dictionary:
	var hp: float = float(int(base_stats.get("hp", 0)))
	var attack: float = float(int(base_stats.get("attack", 0)))
	var defense: float = float(int(base_stats.get("defense", 0)))
	var xp: float = float(int(base_stats.get("xp", 0)))
	var gold: float = float(int(base_stats.get("gold", 0)))

	# Level growth. The per-kind base profile (#378) is the floor-1 stat for
	# this cohort; growth measures how far above that floor-1 level the mob
	# currently is. EnemyLevel keeps per-kind offsets constant across floors,
	# so level - floor_1_kind_level == FLOOR_BASELINE_STEP * (floor - 1) for
	# every kind — using floor depth here keeps the module kind-agnostic and
	# still produces identity at floor 1 regardless of what `level` says.
	# The `level` parameter is intentionally accepted (and unused in this
	# slice's math) so #380's elite scaling spike can route through a higher
	# level without changing the signature.
	var depth: int = maxi(0, floor_number - 1)
	if depth > 0:
		var level_delta: int = depth * EnemyLevel.FLOOR_BASELINE_STEP
		var lf: float = float(level_delta)
		hp *= 1.0 + HP_GROWTH_PER_LEVEL * lf
		attack *= 1.0 + ATTACK_GROWTH_PER_LEVEL * lf
		if defense > 0.0:
			defense *= 1.0 + DEFENSE_GROWTH_PER_LEVEL * lf
		xp *= 1.0 + XP_GROWTH_PER_LEVEL * lf
		gold *= 1.0 + GOLD_GROWTH_PER_LEVEL * lf

	# Party-size mult — reuse BossScaling tables so standard mobs and bosses
	# share the same party curve. HP and attack only.
	var effective_party: int = party_size if party_size > 0 else 1
	var clamped_party: int = clampi(effective_party, 1, 4)
	hp *= float(BossScaling.PARTY_HP_MULT[clamped_party - 1])
	attack *= float(BossScaling.PARTY_ATTACK_MULT[clamped_party - 1])

	# Average-party-level mult — clamped to [0.7, 2.0]. Negative
	# floor_baseline_level is the "skip" sentinel (matches BossScaling) so
	# legacy / pre-#379 callers and tests that only pass floor/party get
	# unchanged behavior.
	if floor_baseline_level >= 0:
		var raw: float = 1.0 + BossScaling.LEVEL_MULT_PER_LEVEL_DIFF * (avg_party_level - float(floor_baseline_level))
		# Elite path skips the downward clamp — an elite is never scaled below
		# its honest 1.0× value. Upward clamp stays so an overleveled party
		# still sees the LEVEL_MULT_MAX ceiling (#380 acceptance criterion).
		var lower: float = ELITE_LEVEL_MULT_MIN if is_elite else BossScaling.LEVEL_MULT_MIN
		var level_mult: float = clampf(raw, lower, BossScaling.LEVEL_MULT_MAX)
		hp *= level_mult
		attack *= level_mult

	# Elite reward bonus — applied last so xp/gold growth from the floor curve
	# flows through, then 2.5× on top. Party-size / party-level mults still
	# skip xp/gold (same no-double-dip contract as the non-elite path).
	if is_elite:
		xp *= ELITE_REWARD_MULT
		gold *= ELITE_REWARD_MULT

	return {
		"hp": int(roundf(hp)),
		"attack": int(roundf(attack)),
		"defense": int(roundf(defense)),
		"xp": int(roundf(xp)),
		"gold": int(roundf(gold)),
	}
