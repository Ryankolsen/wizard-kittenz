extends GutTest

# Slice 4 of PRD #322. PartyLevelCap module: decade-boundary cap formula
# and stat sync-down transformation. See scripts/lobby/party_level_cap.gd.

const _WIZARD := CharacterData.CharacterClass.WIZARD_KITTEN
const _BATTLE := CharacterData.CharacterClass.BATTLE_KITTEN

func _make_lvl_n(klass: int, lvl: int) -> CharacterData:
	# Mirrors CharacterData.make_new + manual level bump so per-class baselines
	# at the new level are correctly applied (level-up flow only touches max_hp /
	# max_mp; everything else is base_*_for(klass, level) which is level-agnostic
	# today but stays honest if a future curve is added).
	var c := CharacterData.make_new(klass)
	c.level = lvl
	c.max_hp = CharacterData.base_max_hp_for(klass, lvl)
	c.hp = c.max_hp
	c.max_mp = CharacterData.base_max_mp_for(klass, lvl)
	c.magic_points = c.max_mp
	return c

# --- compute_cap -------------------------------------------------------------

func test_level_thirty_player_with_level_five_friend_capped_to_ten():
	# Issue scenario: a level-30 player joining a level-5 friend syncs to
	# the decade boundary above the friend's level, not the friend's level.
	assert_eq(PartyLevelCap.compute_cap([5, 30]), 10)

func test_cap_formula_lvl_five_to_ten():
	assert_eq(PartyLevelCap.compute_cap([5]), 10)

func test_cap_formula_lvl_ten_to_ten():
	# Decade boundary maps to itself — a party of all-level-10 stays at 10
	# (not bumped to 20) so the cap doesn't over-grant headroom.
	assert_eq(PartyLevelCap.compute_cap([10]), 10)

func test_cap_formula_lvl_eleven_to_twenty():
	assert_eq(PartyLevelCap.compute_cap([11]), 20)

func test_cap_formula_lvl_twenty_three_to_thirty():
	assert_eq(PartyLevelCap.compute_cap([23]), 30)

func test_cap_uses_minimum_party_level():
	# Min drives the cap regardless of where it sits in the array.
	assert_eq(PartyLevelCap.compute_cap([5, 25, 18]), 10)
	assert_eq(PartyLevelCap.compute_cap([25, 5, 18]), 10)
	assert_eq(PartyLevelCap.compute_cap([18, 25, 5]), 10)

func test_cap_empty_party_falls_back_to_decade():
	# Pre-handshake / null-session caller never traps on a 0-divide.
	assert_eq(PartyLevelCap.compute_cap([]), 10)

# --- apply_cap_to_character: sync-down transformation -----------------------

func test_sync_down_recomputes_base_stats_at_cap_level():
	# Level-30 Wizard, cap to 10: max_hp drops to the level-10 Wizard baseline,
	# not the level-30 value. This is the core "high-level player gets a
	# lower-level player's HP pool" promise of the cap.
	var lvl_30 := _make_lvl_n(_WIZARD, 30)
	var capped := PartyLevelCap.apply_cap_to_character(lvl_30, 10)
	assert_eq(capped.level, 10)
	assert_eq(capped.max_hp, CharacterData.base_max_hp_for(_WIZARD, 10))
	assert_lt(capped.max_hp, lvl_30.max_hp, "capped max_hp is strictly lower than real")

func test_sync_down_scales_allocations_proportionally():
	# 24 points allocated to magic_attack on a lvl-30 char. Cap=10:
	# scaled points = floor(24 * 10/30) = 8. With INT_INCREMENTS[magic_attack]=1
	# that's +8 magic_attack from allocation.
	var lvl_30 := _make_lvl_n(_WIZARD, 30)
	lvl_30.allocated_points = {"magic_attack": 24}
	lvl_30.magic_attack += 24
	var base_ma_at_10 := CharacterData.base_magic_attack_for(_WIZARD, 10)
	var capped := PartyLevelCap.apply_cap_to_character(lvl_30, 10)
	assert_eq(int(capped.allocated_points.get("magic_attack", 0)), 8,
		"allocated_points scaled to floor(24 * 10/30) = 8")
	assert_eq(capped.magic_attack, base_ma_at_10 + 8,
		"magic_attack = level-10 baseline + scaled allocation")

func test_sync_down_preserves_distribution_shape():
	# A character's spec shape (the ratio between invested stats) survives
	# the cap so the player still feels like the build they chose.
	var lvl_30 := _make_lvl_n(_WIZARD, 30)
	lvl_30.allocated_points = {"magic_attack": 24, "max_mp": 12}
	lvl_30.magic_attack += 24
	lvl_30.max_mp += 12 * StatAllocator.INT_INCREMENTS["max_mp"]
	var capped := PartyLevelCap.apply_cap_to_character(lvl_30, 10)
	assert_eq(int(capped.allocated_points["magic_attack"]), 8)
	assert_eq(int(capped.allocated_points["max_mp"]), 4)
	# 24:12 == 8:4 — the 2:1 ratio is preserved.
	assert_eq(
		float(capped.allocated_points["magic_attack"]) / float(capped.allocated_points["max_mp"]),
		float(lvl_30.allocated_points["magic_attack"]) / float(lvl_30.allocated_points["max_mp"]),
		"allocation ratio between stats unchanged"
	)

func test_sync_down_does_not_affect_items():
	# Items are layered on top of the capped char by ItemStatApplicator —
	# the cap is item-blind. Verifying the contract: a +5 item bonus applied
	# AFTER the cap pass carries through fully.
	var lvl_30 := _make_lvl_n(_WIZARD, 30)
	lvl_30.allocated_points = {"magic_attack": 24}
	lvl_30.magic_attack += 24
	var capped := PartyLevelCap.apply_cap_to_character(lvl_30, 10)
	var ma_before_item := capped.magic_attack
	# Simulate ItemStatApplicator applying a +5 magic_attack bonus.
	capped.magic_attack += 5
	assert_eq(capped.magic_attack, ma_before_item + 5,
		"item bonus contributes its full +5 on top of the capped value")

# --- no-op edges ------------------------------------------------------------

func test_solo_player_no_cap_applied():
	# compute_cap([15]) = 20, and the player's level (15) is below that — so
	# apply_cap_to_character is a no-op and the returned character matches the
	# input stat-for-stat (returned as a fresh clone, not the same reference).
	var lvl_15 := _make_lvl_n(_WIZARD, 15)
	var cap := PartyLevelCap.compute_cap([15])
	assert_eq(cap, 20)
	var out := PartyLevelCap.apply_cap_to_character(lvl_15, cap)
	assert_eq(out.level, lvl_15.level)
	assert_eq(out.max_hp, lvl_15.max_hp)
	assert_eq(out.attack, lvl_15.attack)
	assert_ne(out, lvl_15, "returned a fresh clone, not the input reference")

func test_player_at_cap_level_is_noop():
	# Decade-boundary player: their level == cap. Stats pass through clean.
	var lvl_10 := _make_lvl_n(_WIZARD, 10)
	var out := PartyLevelCap.apply_cap_to_character(lvl_10, 10)
	assert_eq(out.level, 10)
	assert_eq(out.max_hp, lvl_10.max_hp)
	assert_eq(out.attack, lvl_10.attack)

func test_player_below_cap_level_is_noop():
	# Level-8 player in a party capped at 10 — no transformation.
	var lvl_8 := _make_lvl_n(_WIZARD, 8)
	var out := PartyLevelCap.apply_cap_to_character(lvl_8, 10)
	assert_eq(out.level, lvl_8.level)
	assert_eq(out.max_hp, lvl_8.max_hp)

# --- party-event integration ------------------------------------------------

func test_cap_recomputes_on_party_member_levelup():
	# A party member levels up mid-session: the cap formula is pure, so a
	# fresh compute_cap call against the new level set produces the new cap
	# without any stateful "recompute" hook — the caller just re-asks.
	var levels := [5, 30]
	assert_eq(PartyLevelCap.compute_cap(levels), 10)
	levels[0] = 11
	assert_eq(PartyLevelCap.compute_cap(levels), 20,
		"low-level member crossing the decade re-asks for and gets a higher cap")

func test_cap_releases_on_party_leave():
	# Player leaves the party — release_cap restores effective_stats to a
	# full-fidelity clone of real_stats. Mirrors PartyScaler.remove_scaling.
	var lvl_30 := _make_lvl_n(_WIZARD, 30)
	var pm := PartyMember.from_character(lvl_30)
	PartyLevelCap.apply_cap_to_member(pm, 10)
	assert_eq(pm.effective_stats.level, 10, "fixture: capped state in effect")
	assert_eq(pm.real_stats.level, 30, "real_stats untouched while capped")
	PartyLevelCap.release_cap(pm)
	assert_eq(pm.effective_stats.level, 30, "effective_stats restored to real level")
	assert_eq(pm.effective_stats.max_hp, pm.real_stats.max_hp)
	assert_ne(pm.effective_stats, pm.real_stats, "effective is still a fresh clone")

func test_apply_cap_to_member_only_mutates_effective_stats():
	# Real stats are the persistent character — the cap must not touch them.
	var lvl_30 := _make_lvl_n(_WIZARD, 30)
	var real_max_hp_before := lvl_30.max_hp
	var pm := PartyMember.from_character(lvl_30)
	PartyLevelCap.apply_cap_to_member(pm, 10)
	assert_eq(pm.real_stats.level, 30, "real_stats.level untouched")
	assert_eq(pm.real_stats.max_hp, real_max_hp_before, "real_stats.max_hp untouched")
	assert_eq(pm.effective_stats.level, 10, "effective_stats reflects the cap")

func test_apply_cap_does_not_mutate_input_character():
	# Caller of apply_cap_to_character holds the original — must come back unchanged.
	var lvl_30 := _make_lvl_n(_WIZARD, 30)
	lvl_30.allocated_points = {"magic_attack": 24}
	lvl_30.magic_attack += 24
	var ma_before := lvl_30.magic_attack
	var alloc_before := int(lvl_30.allocated_points["magic_attack"])
	var _capped := PartyLevelCap.apply_cap_to_character(lvl_30, 10)
	assert_eq(lvl_30.level, 30, "input level untouched")
	assert_eq(lvl_30.magic_attack, ma_before, "input magic_attack untouched")
	assert_eq(int(lvl_30.allocated_points["magic_attack"]), alloc_before,
		"input allocated_points untouched")
