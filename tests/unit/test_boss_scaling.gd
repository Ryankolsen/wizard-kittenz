extends GutTest

# Tests for BossScaling — pure-function module that applies boss multipliers
# + per-floor scaling to a base-stat dictionary. Single source of truth for
# boss stat math (PRD #322 / issue #323).

# --- core wiring: the slice-1 balance change -------------------------------

func test_floor_one_vacuum_boss_attack_is_five():
	# The single most important assertion: BOSS_ATTACK_MULT dropped from 4
	# to 2.5, so the floor-1 vacuum boss (base attack 2) now hits for 5
	# instead of 8. A level-1 Battle Kitten (10 hp, 1 def) survives ~3 hits.
	var scaled := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 1)
	assert_eq(scaled["attack"], 5)

func test_boss_attack_mult_is_two_point_five():
	# Pin the constant directly so a future drift back to 4 (or any other
	# value) is loud, not silently absorbed by changing base stats.
	assert_eq(BossScaling.BOSS_ATTACK_MULT, 2.5)

# --- content details: full floor-1 vacuum boss stat shape ------------------

func test_floor_one_vacuum_boss_full_stats():
	var scaled := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 1)
	assert_eq(scaled["hp"], 48, "8 * BOSS_HP_MULT(6)")
	assert_eq(scaled["attack"], 5, "2 * BOSS_ATTACK_MULT(2.5)")
	assert_eq(scaled["defense"], 0, "base def 0 stays 0")
	assert_eq(scaled["xp"], 45, "15 * BOSS_XP_MULT(3)")
	assert_eq(scaled["gold"], 8, "2 * BOSS_GOLD_MULT(4)")

func test_floor_three_scaling_applied():
	# floor 3 → depth 2 → hp_mult = 1 + 0.55 * 2 = 2.10
	# vacuum: 8 * 6 = 48 base boss hp; 48 * 2.10 = 100.8 → 101.
	var scaled := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 3)
	assert_eq(scaled["hp"], 101, "48 * 2.10 rounded")
	# attack: 2 * 2.5 = 5 base; 5 * (1 + 0.35*2) = 5 * 1.70 = 8.5 → 9.
	assert_eq(scaled["attack"], 9)

func test_dog_knight_defense_multiplier():
	# Dog Knight base defense is 2. Boss multiplier 3 → defense 6 at floor 1
	# (no floor scaling at depth 0).
	var scaled := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 2, "xp": 15, "gold": 2}, 1)
	assert_eq(scaled["defense"], 6, "2 * BOSS_DEFENSE_MULT(3)")

# --- edge cases ------------------------------------------------------------

func test_floor_zero_treated_as_floor_one():
	# Defensive against a stale caller passing 0 or a negative floor —
	# the scaling clamps to depth 0 so no negative multipliers leak in.
	var f0 := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 0)
	var f1 := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 1)
	assert_eq(f0, f1, "floor 0 = floor 1 (no negative scaling)")

func test_negative_floor_treated_as_floor_one():
	var fn := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, -3)
	var f1 := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 1)
	assert_eq(fn, f1)

func test_zero_base_defense_stays_zero_across_floors():
	# Mirrors the planner's pre-extraction contract: a zero base defense
	# stays zero on every floor (no scaling from nothing). The Dog Knight
	# exception is the only kind with nonzero base defense today.
	var scaled := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 5)
	assert_eq(scaled["defense"], 0)

func test_missing_keys_default_to_zero():
	# Defensive: a partial dict (e.g. forgot to pass gold) should not crash.
	var scaled := BossScaling.compute_boss_stats({"hp": 8, "attack": 2}, 1)
	assert_eq(scaled["defense"], 0)
	assert_eq(scaled["xp"], 0)
	assert_eq(scaled["gold"], 0)

func test_higher_floor_strictly_increases_stats():
	# Monotonic: a deeper-floor boss is strictly nastier than the floor-1
	# version of the same stat block (with nonzero base everywhere).
	var f1 := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 2, "xp": 15, "gold": 2}, 1)
	var f5 := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 2, "xp": 15, "gold": 2}, 5)
	assert_gt(f5["hp"], f1["hp"])
	assert_gt(f5["attack"], f1["attack"])
	assert_gt(f5["defense"], f1["defense"])
	assert_gt(f5["xp"], f1["xp"])
	assert_gt(f5["gold"], f1["gold"])

# --- integration: planner uses BossScaling ---------------------------------

func test_room_spawn_planner_uses_boss_scaling():
	# Locks the contract that a boss spawned via plan_enemy has stats matching
	# BossScaling.compute_boss_stats for the same inputs. The planner is the
	# only production consumer today — drift here would silently rebalance
	# every boss spawn.
	var room := Room.make(7, Room.TYPE_BOSS)
	room.enemy_kind = EnemyData.EnemyKind.ROGUE_ROOMBA
	var d := RoomSpawnPlanner.plan_enemy(room, 0, 1)
	var scaled := BossScaling.compute_boss_stats({
		"hp": EnemyData.base_max_hp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"attack": EnemyData.base_attack_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"defense": EnemyData.base_defense_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"xp": EnemyData.base_xp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"gold": EnemyData.base_gold_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
	}, 1)
	assert_eq(d.max_hp, scaled["hp"])
	assert_eq(d.attack, scaled["attack"])
	assert_eq(d.defense, scaled["defense"])
	assert_eq(d.xp_reward, scaled["xp"])
	assert_eq(d.gold_reward, scaled["gold"])

func test_room_spawn_planner_floor_three_matches_boss_scaling():
	# Same contract at a non-baseline floor — the planner threads floor_number
	# through to BossScaling so floor scaling is computed once, not twice.
	var room := Room.make(7, Room.TYPE_BOSS)
	room.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	var d := RoomSpawnPlanner.plan_enemy(room, 0, 3)
	var scaled := BossScaling.compute_boss_stats({
		"hp": EnemyData.base_max_hp_for(EnemyData.EnemyKind.DOG_KNIGHT),
		"attack": EnemyData.base_attack_for(EnemyData.EnemyKind.DOG_KNIGHT),
		"defense": EnemyData.base_defense_for(EnemyData.EnemyKind.DOG_KNIGHT),
		"xp": EnemyData.base_xp_for(EnemyData.EnemyKind.DOG_KNIGHT),
		"gold": EnemyData.base_gold_for(EnemyData.EnemyKind.DOG_KNIGHT),
	}, 3)
	assert_eq(d.max_hp, scaled["hp"])
	assert_eq(d.attack, scaled["attack"])
	assert_eq(d.defense, scaled["defense"])
