extends GutTest

# Tests for StandardEnemyScaling — pure-function module that scales a standard
# mob's per-kind base profile by level (depth-driven), floor, party size, and
# party-level guardrail. Counterpart to BossScaling for the non-boss path
# (PRD #376 / issue #379).

# --- core wiring / identity ------------------------------------------------

func test_floor_one_solo_is_identity():
	# Floor 1, solo, on-baseline → unchanged per-kind base profile. Pins the
	# "floor 1 displays exactly the #378 base profile" promise.
	var scaled := StandardEnemyScaling.compute_standard_stats(
		{"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}, 4, 1, 1)
	assert_eq(scaled["hp"], 24)
	assert_eq(scaled["attack"], 4)
	assert_eq(scaled["defense"], 2)
	assert_eq(scaled["xp"], 15)
	assert_eq(scaled["gold"], 2)

# --- level growth ----------------------------------------------------------

func test_higher_floor_grows_hp_and_attack():
	# Dog Knight base (24/4/2) on floor 2. Floor depth 1 → level_delta = 2
	# (EnemyLevel.FLOOR_BASELINE_STEP). With the chosen growth constants:
	#   hp 24 * (1 + 0.15*2) = 24 * 1.30 = 31.2 → 31
	#   atk 4 * (1 + 0.10*2) = 4 * 1.20 = 4.8 → 5
	#   def 2 * (1 + 0.05*2) = 2 * 1.10 = 2.2 → 2
	var scaled := StandardEnemyScaling.compute_standard_stats(
		{"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}, 6, 2, 1)
	assert_eq(scaled["hp"], 31)
	assert_eq(scaled["attack"], 5)
	assert_eq(scaled["defense"], 2)
	# Sanity vs. floor 1 baseline.
	var f1 := StandardEnemyScaling.compute_standard_stats(
		{"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}, 4, 1, 1)
	assert_gt(scaled["hp"], f1["hp"])
	assert_gt(scaled["attack"], f1["attack"])

func test_zero_defense_never_grows():
	# Pigeon base defense 0 stays at 0 across floors — no "scaling from
	# nothing" (mirrors BossScaling's contract).
	var f1 := StandardEnemyScaling.compute_standard_stats(
		{"hp": 6, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 1, 1, 1)
	var f5 := StandardEnemyScaling.compute_standard_stats(
		{"hp": 6, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 9, 5, 1)
	assert_eq(f1["defense"], 0)
	assert_eq(f5["defense"], 0)

# --- party guardrails ------------------------------------------------------

func test_party_of_four_raises_hp():
	# Floor 1 identity for level growth + party-size table from BossScaling:
	#   HP mult 2.0, attack mult 1.3.
	var base := {"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}
	var scaled := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 4)
	assert_eq(scaled["hp"], int(roundf(24.0 * 2.0)))
	assert_eq(scaled["attack"], int(roundf(4.0 * 1.3)))
	# Defense / xp / gold not party-scaled.
	assert_eq(scaled["defense"], 2)
	assert_eq(scaled["xp"], 15)
	assert_eq(scaled["gold"], 2)

func test_underleveled_party_softened():
	# avg=0, baseline=3 → diff=-3 → mult = 1 + 0.08*(-3) = 0.76. Above the
	# 0.7 clamp floor, so the raw 0.76 applies. Dog Knight base (24/4) so
	# both hp and attack visibly drop after rounding.
	var base := {"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}
	var scaled := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 1, 0.0, 3)
	assert_lt(scaled["hp"], base["hp"], "underleveled party gets a softer mob")
	assert_lt(scaled["attack"], base["attack"])
	assert_gte(scaled["hp"], int(roundf(float(base["hp"]) * BossScaling.LEVEL_MULT_MIN)),
		"never softer than 0.7×")

func test_overleveled_party_clamped():
	# avg=50, baseline=3 → raw mult 4.76, clamps to 2.0. hp = 24 * 2.0 = 48.
	var base := {"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}
	var scaled := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 1, 50.0, 3)
	assert_eq(scaled["hp"], int(roundf(24.0 * BossScaling.LEVEL_MULT_MAX)))
	assert_eq(scaled["attack"], int(roundf(4.0 * BossScaling.LEVEL_MULT_MAX)))

# --- defensive inputs ------------------------------------------------------

func test_missing_keys_and_party_clamp():
	# Partial base dict defaults missing keys to 0.
	var partial := StandardEnemyScaling.compute_standard_stats({"hp": 8, "attack": 2}, 1, 1, 1)
	assert_eq(partial["defense"], 0)
	assert_eq(partial["xp"], 0)
	assert_eq(partial["gold"], 0)
	# party_size 0 → solo (1).
	var base := {"hp": 6, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var p0 := StandardEnemyScaling.compute_standard_stats(base, 1, 1, 0)
	var p1 := StandardEnemyScaling.compute_standard_stats(base, 1, 1, 1)
	assert_eq(p0, p1)
	# party_size 9 → clamps to 4.
	var p9: Dictionary = StandardEnemyScaling.compute_standard_stats(base, 1, 1, 9)
	var p4: Dictionary = StandardEnemyScaling.compute_standard_stats(base, 1, 1, 4)
	assert_eq(p9, p4)

# --- elites (PRD #376 / issue #380) ----------------------------------------

func test_elite_not_softened_for_underleveled():
	# avg=0, baseline=3 → raw mult 0.76. Non-elite applies that softening;
	# elite skips the downward clamp and stays at the honest 1.0×.
	var base := {"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}
	var non_elite := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 1, 0.0, 3, false)
	var elite := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 1, 0.0, 3, true)
	assert_lt(non_elite["hp"], base["hp"], "non-elite is softened by underleveled party")
	assert_eq(elite["hp"], base["hp"], "elite floor 1 identity holds — no downward softening")
	assert_eq(elite["attack"], base["attack"], "elite attack not softened")
	assert_gt(elite["hp"], non_elite["hp"], "elite tougher than the same-kind non-elite for an underleveled party")

func test_elite_still_scales_up():
	# Upward party-level clamp still applies for elites: avg=50, baseline=3
	# clamps to 2.0× just like non-elites. Party-size mult also still applies.
	var base := {"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}
	var elite_over := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 1, 50.0, 3, true)
	assert_eq(elite_over["hp"], int(roundf(24.0 * BossScaling.LEVEL_MULT_MAX)),
		"elite still clamps at LEVEL_MULT_MAX for overleveled party")
	assert_eq(elite_over["attack"], int(roundf(4.0 * BossScaling.LEVEL_MULT_MAX)))
	# 4-player elite: floor 1 identity (no level growth), no avg/baseline so
	# only the party-size mult applies.
	var elite_quad := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 4, -1.0, -1, true)
	assert_eq(elite_quad["hp"], int(roundf(24.0 * 2.0)),
		"elite still gets the 4-player party HP bump")
	assert_eq(elite_quad["attack"], int(roundf(4.0 * 1.3)))

func test_elite_rewards_multiplied():
	# Floor 1 solo on-baseline → identity scaling so the 2.5× multiplier lands
	# exactly. Elite xp/gold = round(non_elite * 2.5).
	var base := {"hp": 24, "attack": 4, "defense": 2, "xp": 15, "gold": 2}
	var non_elite := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 1, -1.0, -1, false)
	var elite := StandardEnemyScaling.compute_standard_stats(base, 4, 1, 1, -1.0, -1, true)
	assert_eq(elite["xp"], int(roundf(float(non_elite["xp"]) * StandardEnemyScaling.ELITE_REWARD_MULT)))
	assert_eq(elite["gold"], int(roundf(float(non_elite["gold"]) * StandardEnemyScaling.ELITE_REWARD_MULT)))
	# Sanity: stats not multiplied — only xp/gold get the elite bonus.
	assert_eq(elite["hp"], non_elite["hp"], "elite reward bump doesn't leak into hp")
	assert_eq(elite["attack"], non_elite["attack"])
