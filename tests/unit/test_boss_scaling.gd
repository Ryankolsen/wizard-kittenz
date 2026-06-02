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

# --- party-size scaling (issue #324) ---------------------------------------

func test_party_of_four_doubles_boss_hp():
	# Headline assertion: a 4-player run gets 2.0× boss hp on top of the
	# floor-1 multiplier. Vacuum base hp 8 → 8 * 6 = 48 → 48 * 2.0 = 96.
	var scaled := BossScaling.compute_boss_stats(
		{"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}, 1, 4)
	assert_eq(scaled["hp"], 96)

func test_party_size_hp_multipliers_match_table():
	# PRD #322 party-size hp table: 1→1.0, 2→1.4, 3→1.75, 4→2.0.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	# Solo baseline: 8 * 6 = 48.
	assert_eq(BossScaling.compute_boss_stats(base, 1, 1)["hp"], 48)
	# 2-player: 48 * 1.4 = 67.2 → 67.
	assert_eq(BossScaling.compute_boss_stats(base, 1, 2)["hp"], 67)
	# 3-player: 48 * 1.75 = 84.
	assert_eq(BossScaling.compute_boss_stats(base, 1, 3)["hp"], 84)
	# 4-player: 48 * 2.0 = 96.
	assert_eq(BossScaling.compute_boss_stats(base, 1, 4)["hp"], 96)

func test_party_size_attack_multipliers_match_table():
	# PRD #322 party-size attack table: 1→1.0, 2→1.1, 3→1.2, 4→1.3. Base
	# vacuum attack 2 → 2 * 2.5 = 5 floor-1 solo.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	assert_eq(BossScaling.compute_boss_stats(base, 1, 1)["attack"], 5)
	# 5 * 1.1 = 5.5 → 6.
	assert_eq(BossScaling.compute_boss_stats(base, 1, 2)["attack"], 6)
	# 5 * 1.2 = 6.0 → 6.
	assert_eq(BossScaling.compute_boss_stats(base, 1, 3)["attack"], 6)
	# 5 * 1.3 = 6.5 → 7 (banker's rounding via roundf — Godot rounds .5 up).
	assert_eq(BossScaling.compute_boss_stats(base, 1, 4)["attack"], 7)

func test_party_size_does_not_affect_defense_xp_gold():
	# PRD #322: only HP and attack scale with party size. Defense, xp, gold
	# stay solo-equivalent so 4-player runs don't double-dip on rewards
	# (per-kill split already shares them) and the Dog Knight defense curve
	# isn't doubled past its design point.
	var base := {"hp": 8, "attack": 2, "defense": 2, "xp": 15, "gold": 2}
	var solo := BossScaling.compute_boss_stats(base, 1, 1)
	var four := BossScaling.compute_boss_stats(base, 1, 4)
	assert_eq(four["defense"], solo["defense"])
	assert_eq(four["xp"], solo["xp"])
	assert_eq(four["gold"], solo["gold"])

func test_party_size_composes_with_floor():
	# Multipliers stack multiplicatively: floor and party are independent
	# axes, not "max of." Floor 3 + party 2: hp = 8 * 6 (boss) * 2.10 (floor
	# depth 2 at 0.55/level) * 1.4 (party 2) = 141.12 → 141.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var scaled := BossScaling.compute_boss_stats(base, 3, 2)
	assert_eq(scaled["hp"], 141)
	# attack: 2 * 2.5 * 1.70 * 1.1 = 9.35 → 9.
	assert_eq(scaled["attack"], 9)

func test_party_size_zero_treated_as_solo():
	# Defensive: a pre-handshake / null-session caller may pass 0 rather
	# than 1. The function clamps 0 → solo so honest-but-stale input
	# doesn't silently zero out boss stats via PARTY_*_MULT[-1].
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var p0 := BossScaling.compute_boss_stats(base, 1, 0)
	var p1 := BossScaling.compute_boss_stats(base, 1, 1)
	assert_eq(p0, p1)

func test_party_size_above_four_clamped_to_four():
	# Defensive: party_size > 4 (an oversized lobby, a future expansion)
	# clamps to the 4-player multiplier rather than indexing past the
	# table.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var p8 := BossScaling.compute_boss_stats(base, 1, 8)
	var p4 := BossScaling.compute_boss_stats(base, 1, 4)
	assert_eq(p8, p4)

func test_party_size_default_argument_is_solo():
	# Old call sites (still passing only floor) get solo scaling. Locks
	# in the default so a future signature drift is loud.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var default_call := BossScaling.compute_boss_stats(base, 1)
	var explicit_solo := BossScaling.compute_boss_stats(base, 1, 1)
	assert_eq(default_call, explicit_solo)

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

# --- average-party-level multiplier (issue #325) ---------------------------

func test_party_at_baseline_level_no_scaling():
	# A party whose average level matches the floor's baseline gets the boss
	# at design difficulty: 1.0 + 0.08 * 0 = 1.0. Floor-1 vacuum stays at
	# hp=48, attack=5.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var scaled := BossScaling.compute_boss_stats(base, 1, 1, 3.0, 3)
	assert_eq(scaled["hp"], 48, "avg=baseline → mult=1.0")
	assert_eq(scaled["attack"], 5)

func test_party_five_levels_over_baseline():
	# avg=8, baseline=3 → diff=5 → mult = 1.0 + 0.08*5 = 1.4. Vacuum hp =
	# 48 * 1.4 = 67.2 → 67. attack 5 * 1.4 = 7.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var scaled := BossScaling.compute_boss_stats(base, 1, 1, 8.0, 3)
	assert_eq(scaled["hp"], 67)
	assert_eq(scaled["attack"], 7)

func test_party_under_baseline_clamped_to_seven_tenths():
	# Extreme below-baseline: avg=-10 (defensive; not a value the planner
	# would emit, but the clamp is what keeps the math safe regardless).
	# Raw = 1.0 + 0.08 * (-10 - 3) = -0.04, clamped to LEVEL_MULT_MIN (0.7).
	# Vacuum hp = 48 * 0.7 ≈ 33.6 → 34 (Godot roundf rounds half away from zero).
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var scaled := BossScaling.compute_boss_stats(base, 1, 1, -10.0, 3)
	assert_eq(scaled["hp"], 34, "clamped to 0.7×")

func test_party_over_baseline_clamped_to_two():
	# Extreme over-baseline: avg=50, baseline=3. Raw = 4.76 → clamp to
	# LEVEL_MULT_MAX (2.0). Vacuum hp = 48 * 2.0 = 96.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var scaled := BossScaling.compute_boss_stats(base, 1, 1, 50.0, 3)
	assert_eq(scaled["hp"], 96)

func test_level_mult_does_not_affect_defense_xp_gold():
	# PRD #322: level mult applies to HP and attack only. A high-level party
	# doesn't multiply rewards (per-kill split already shares them) and
	# doesn't double-pump Dog-Knight-style defense.
	var base := {"hp": 8, "attack": 2, "defense": 2, "xp": 15, "gold": 2}
	var solo := BossScaling.compute_boss_stats(base, 1, 1, 3.0, 3)
	var high := BossScaling.compute_boss_stats(base, 1, 1, 20.0, 3)
	assert_eq(high["defense"], solo["defense"])
	assert_eq(high["xp"], solo["xp"])
	assert_eq(high["gold"], solo["gold"])

func test_level_mult_composes_with_party_size():
	# Multipliers stack multiplicatively. Party 4 (hp ×2.0) + level diff +5
	# (mult 1.4): 48 × 2.0 × 1.4 = 134.4 → 134.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var scaled := BossScaling.compute_boss_stats(base, 1, 4, 8.0, 3)
	assert_eq(scaled["hp"], 134)

func test_floor_baseline_lookup_table():
	# Per PRD #322: floor 1 → 3, floor 2 → 5, floor 3 → 7, +2/floor.
	assert_eq(BossScaling.baseline_level_for_floor(1), 3)
	assert_eq(BossScaling.baseline_level_for_floor(2), 5)
	assert_eq(BossScaling.baseline_level_for_floor(3), 7)
	assert_eq(BossScaling.baseline_level_for_floor(5), 11)

func test_baseline_level_for_floor_clamps_below_one():
	# Defensive: floor 0 / negative clamp to floor 1's baseline so a stale
	# caller doesn't get a sub-3 baseline that would inflate the level mult.
	assert_eq(BossScaling.baseline_level_for_floor(0), 3)
	assert_eq(BossScaling.baseline_level_for_floor(-5), 3)

func test_level_mult_default_arg_skips_scaling():
	# Old call sites (compute_boss_stats(base, floor) or (base, floor, party))
	# don't pass avg/baseline; the function must skip level scaling so their
	# results don't silently shift. Pins the no-arg-default contract.
	var base := {"hp": 8, "attack": 2, "defense": 0, "xp": 15, "gold": 2}
	var with_default := BossScaling.compute_boss_stats(base, 1, 1)
	var with_neg_sentinel := BossScaling.compute_boss_stats(base, 1, 1, -1.0, -1)
	assert_eq(with_default, with_neg_sentinel)
	# And neither matches a level-scaled call (sanity check that the path
	# is actually reachable when the args are supplied).
	var scaled := BossScaling.compute_boss_stats(base, 1, 1, 8.0, 3)
	assert_ne(with_default["hp"], scaled["hp"])

func test_room_spawn_planner_computes_avg_party_level():
	# Planner-side wiring: register_room_enemies must average the session's
	# member levels and pass that into BossScaling. Three members at levels
	# 5/10/15 → avg=10. baseline (floor 1) = 3. diff=7 → mult=1.56.
	var session := _make_session_with_levels([5, 10, 15])
	var room := Room.make(7, Room.TYPE_BOSS)
	room.enemy_kind = EnemyData.EnemyKind.ROGUE_ROOMBA
	var spawned := RoomSpawnPlanner.register_room_enemies(session, room, 1)
	var expected := BossScaling.compute_boss_stats({
		"hp": EnemyData.base_max_hp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"attack": EnemyData.base_attack_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"defense": EnemyData.base_defense_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"xp": EnemyData.base_xp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"gold": EnemyData.base_gold_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
	}, 1, 3, 10.0, 3)
	assert_eq(spawned[0].max_hp, expected["hp"])
	assert_eq(spawned[0].attack, expected["attack"])

func test_room_spawn_planner_empty_party_uses_level_one():
	# Defensive: a null / empty-member session falls back to avg_party_level
	# = 1.0 rather than crashing on a 0-divide. With floor-1 baseline=3,
	# diff=-2 → mult=0.84.
	var room := Room.make(7, Room.TYPE_BOSS)
	room.enemy_kind = EnemyData.EnemyKind.ROGUE_ROOMBA
	var spawned := RoomSpawnPlanner.register_room_enemies(null, room, 1)
	var expected := BossScaling.compute_boss_stats({
		"hp": EnemyData.base_max_hp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"attack": EnemyData.base_attack_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"defense": EnemyData.base_defense_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"xp": EnemyData.base_xp_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
		"gold": EnemyData.base_gold_for(EnemyData.EnemyKind.ROGUE_ROOMBA),
	}, 1, 1, 1.0, 3)
	assert_eq(spawned[0].max_hp, expected["hp"], "null session falls back to avg=1")

# --- helpers ---------------------------------------------------------------

func _make_session_with_levels(levels: Array) -> CoopSession:
	# Builds a CoopSession with one member per supplied level. Used by the
	# planner-side avg-party-level tests so we can pin a specific arithmetic
	# mean without depending on CharacterFactory defaults.
	var lobby := LobbyState.new()
	lobby.room_code = "ABCDE"
	var characters: Dictionary = {}
	for i in range(levels.size()):
		var pid := "p%d" % (i + 1)
		var p := LobbyPlayer.make(pid, "K%d" % (i + 1), "Mage", i == 0)
		lobby.add_player(p)
		var c := CharacterFactory.create_default("Mage")
		c.level = int(levels[i])
		characters[pid] = c
	var s := CoopSession.new(lobby, characters)
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	start.connections = [1]
	d.add_room(start)
	d.add_room(boss)
	d.start_id = 0
	d.boss_id = 1
	s.start(d)
	return s
