extends GutTest

const _NEW_KINDS := [
	EnemyData.EnemyKind.ANGRY_PIGEON,
	EnemyData.EnemyKind.ROGUE_ROOMBA,
	EnemyData.EnemyKind.DOG_KNIGHT,
	EnemyData.EnemyKind.CATNIP_DEALER,
	EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE,
]

# PRD #297 slice 2: the 9 boss-only kinds added at the tail of EnemyKind.
# Each must round-trip through make_new with the expected display name and
# share the same boss-tier base stats (sprite-only differentiation).
const _BOSS_KINDS_AND_NAMES := [
	[EnemyData.EnemyKind.SIR_PICKLETON, "Sir Pickleton"],
	[EnemyData.EnemyKind.OLD_LADY_PEARL, "Old Lady Pearl"],
	[EnemyData.EnemyKind.TRASH_PANDA_TYRONE, "Trash Panda Tyrone"],
	[EnemyData.EnemyKind.BIG_BRUISER_BUSTER, "Big Bruiser Buster"],
	[EnemyData.EnemyKind.LAST_CALL_LARRY, "Last Call Larry"],
	[EnemyData.EnemyKind.THE_BOUNCER, "The Bouncer"],
	[EnemyData.EnemyKind.DJ_DUBSTEP, "DJ Dubstep"],
	[EnemyData.EnemyKind.KARAOKE_KAREN, "Karaoke Karen"],
	[EnemyData.EnemyKind.WARDEN_WRETCHED, "Warden Wretched"],
]

# The stat every kind falls back to when base_max_hp_for has no case for it.
# Pinned here so the "no boss still uses the fallback" test below fails for the
# right reason rather than against a magic number copied from the source.
const _GENERIC_FALLBACK_MAX_HP := 8

func test_make_new_angry_pigeon_has_expected_defaults():
	var e := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_eq(e.kind, EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_eq(e.enemy_name, "Angry Pigeon")
	assert_eq(e.max_hp, 6)
	assert_eq(e.hp, 6)
	assert_eq(e.attack, 2)
	assert_eq(e.defense, 0)
	assert_eq(e.xp_reward, 15)
	assert_eq(e.gold_reward, 2)
	assert_eq(e.enemy_id, "", "fresh spawn has no id until the spawn layer mints one")
	assert_false(e.is_boss, "non-boss by default")

func test_enum_has_expected_values():
	# 5 original regular-enemy kinds + 9 boss-only kinds added by PRD #297 slice 1.
	# Asserting the keys pins down both the count and the spelling, so a typo or
	# stray addition fails loudly.
	var names := EnemyData.EnemyKind.keys()
	assert_eq(names.size(), 14)
	var expected := [
		"ANGRY_PIGEON", "ROGUE_ROOMBA", "DOG_KNIGHT", "CATNIP_DEALER", "HAUNTED_SPRAY_BOTTLE",
		"SIR_PICKLETON", "OLD_LADY_PEARL", "TRASH_PANDA_TYRONE", "BIG_BRUISER_BUSTER",
		"LAST_CALL_LARRY", "THE_BOUNCER", "DJ_DUBSTEP", "KARAOKE_KAREN", "WARDEN_WRETCHED",
	]
	for n in expected:
		assert_true(names.has(n), "EnemyKind missing %s" % n)
	for old in ["SLIME", "BAT", "RAT"]:
		assert_false(names.has(old), "EnemyKind still contains retired %s" % old)

# PRD #376 / issue #378: per-kind base stat profiles replace the uniform
# 8/2/0 baseline. Each kind has a distinct role; the pinned values below
# encode that spec — adjust together with EnemyData.base_*_for if tuning.
const _EXPECTED_PROFILES := {
	EnemyData.EnemyKind.ANGRY_PIGEON: [6, 2, 0],
	EnemyData.EnemyKind.ROGUE_ROOMBA: [12, 3, 0],
	EnemyData.EnemyKind.CATNIP_DEALER: [14, 3, 0],
	EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE: [10, 4, 0],
	EnemyData.EnemyKind.DOG_KNIGHT: [24, 4, 2],
}

func test_pigeon_base_profile():
	assert_eq(EnemyData.base_max_hp_for(EnemyData.EnemyKind.ANGRY_PIGEON), 6)
	assert_eq(EnemyData.base_attack_for(EnemyData.EnemyKind.ANGRY_PIGEON), 2)
	assert_eq(EnemyData.base_defense_for(EnemyData.EnemyKind.ANGRY_PIGEON), 0)

func test_dog_knight_is_tanky():
	assert_eq(EnemyData.base_max_hp_for(EnemyData.EnemyKind.DOG_KNIGHT), 24)
	assert_eq(EnemyData.base_defense_for(EnemyData.EnemyKind.DOG_KNIGHT), 2)
	assert_gt(
		EnemyData.base_max_hp_for(EnemyData.EnemyKind.DOG_KNIGHT),
		EnemyData.base_max_hp_for(EnemyData.EnemyKind.ANGRY_PIGEON))

func test_remaining_kind_profiles():
	# Roomba 12/3/0, Catnip 14/3/0, Spray 10/4/0.
	for k in [
		EnemyData.EnemyKind.ROGUE_ROOMBA,
		EnemyData.EnemyKind.CATNIP_DEALER,
		EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE,
	]:
		var p: Array = _EXPECTED_PROFILES[k]
		assert_eq(EnemyData.base_max_hp_for(k), p[0], "kind %d hp" % k)
		assert_eq(EnemyData.base_attack_for(k), p[1], "kind %d attack" % k)
		assert_eq(EnemyData.base_defense_for(k), p[2], "kind %d defense" % k)

func test_make_new_uses_profile():
	var d := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	assert_eq(d.max_hp, 24)
	assert_eq(d.hp, 24)
	assert_eq(d.defense, 2)

func test_only_dog_knight_has_defense():
	for k in _NEW_KINDS:
		if k == EnemyData.EnemyKind.DOG_KNIGHT:
			continue
		assert_eq(EnemyData.base_defense_for(k), 0, "kind %d should have 0 defense" % k)

func test_display_names_are_non_empty_and_distinct():
	var names := []
	for k in _NEW_KINDS:
		var n := EnemyData.display_name_for(k)
		assert_ne(n, "", "display name must not be empty for kind %d" % k)
		assert_false(names.has(n), "display name %s appeared twice" % n)
		names.append(n)
	assert_eq(names.size(), 5)

func test_make_new_round_trip_names():
	assert_eq(EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON).enemy_name, "Angry Pigeon")
	assert_eq(EnemyData.make_new(EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE).enemy_name, "Haunted Spray Bottle")
	assert_eq(EnemyData.make_new(EnemyData.EnemyKind.CATNIP_DEALER).enemy_name, "Catnip Dealer")

func test_take_damage_clamps_and_kills():
	var e := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	assert_true(e.is_alive())
	assert_eq(e.take_damage(2), 2)
	assert_eq(e.hp, 22)
	assert_eq(e.take_damage(99), 22, "overkill returns only damage actually dealt")
	assert_eq(e.hp, 0)
	assert_false(e.is_alive())

func test_make_new_returns_independent_instances():
	var a := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var b := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	a.take_damage(99)
	assert_eq(a.hp, 0)
	assert_eq(b.hp, 6, "second instance should be untouched")

func test_static_helpers_match_make_new():
	for k in _NEW_KINDS:
		var e := EnemyData.make_new(k)
		assert_eq(e.max_hp, EnemyData.base_max_hp_for(k))
		assert_eq(e.attack, EnemyData.base_attack_for(k))
		assert_eq(e.defense, EnemyData.base_defense_for(k))
		assert_eq(e.xp_reward, EnemyData.base_xp_for(k))
		assert_eq(e.gold_reward, EnemyData.base_gold_for(k))
		assert_eq(e.enemy_name, EnemyData.display_name_for(k))

func test_dog_knight_radius_reduced():
	# Issue #260: the prior 200px outlier let DOG_KNIGHT aggro from off-screen
	# on a 480x270 viewport. Pin both the new ceiling and the strict drop from
	# the old value so a regression to 200 (or anything above 120) fails loud.
	var r := EnemyData.base_detection_radius_for(EnemyData.EnemyKind.DOG_KNIGHT)
	assert_lt(r, 200.0, "DOG_KNIGHT must drop below the legacy 200 outlier")
	assert_lte(r, 135.0, "DOG_KNIGHT must respect the 135px viewport half-height ceiling")

func test_detection_radii_are_standardized():
	# Every kind must stay within [MIN, MAX] for the 480x270 viewport so no
	# enemy aggros from off-screen. Exact per-kind values are pinned here so
	# a tweak is a deliberate, reviewed change rather than a silent drift.
	var min_px := 40.0
	var max_px := EnemyData.DETECTION_RADIUS_MAX_PX
	var expected := {
		EnemyData.EnemyKind.ANGRY_PIGEON: 80.0,
		EnemyData.EnemyKind.ROGUE_ROOMBA: 90.0,
		EnemyData.EnemyKind.DOG_KNIGHT: 135.0,
		EnemyData.EnemyKind.CATNIP_DEALER: 75.0,
		EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE: 75.0,
	}
	for k in _NEW_KINDS:
		var r: float = EnemyData.base_detection_radius_for(k)
		assert_gte(r, min_px, "kind %d radius %f below floor" % [k, r])
		assert_lte(r, max_px, "kind %d radius %f above viewport ceiling" % [k, r])
		assert_eq(r, expected[k], "kind %d expected pinned radius" % k)

func test_make_new_stamps_detection_radius():
	# Guards the spawn path: every kind's instance must carry the static
	# helper's value verbatim, otherwise EnemyAI runs on a different number
	# than the test pins above.
	for k in _NEW_KINDS:
		var e := EnemyData.make_new(k)
		assert_eq(e.detection_radius, EnemyData.base_detection_radius_for(k))

func test_make_new_boss_kinds_have_expected_names():
	# PRD #297 slice 2 — every new boss kind round-trips its readable display
	# name through make_new(). Pinned strings drive the boss-name HUD (slice 5).
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		var expected: String = entry[1]
		assert_eq(EnemyData.make_new(k).enemy_name, expected)

func test_boss_kinds_do_not_share_one_base_stat_line():
	# Supersedes the old "sprite-only differentiation" contract (PRD #297
	# slice 2), which required all 9 boss kinds to collapse to a single
	# hp/attack/defense triple. PRD #518 / issue #535 reverses that: each boss
	# gets a profile matching its archetypes, so the cohort must now span more
	# than one value on every axis.
	var hp_set := {}
	var atk_set := {}
	var def_set := {}
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		hp_set[EnemyData.base_max_hp_for(k)] = true
		atk_set[EnemyData.base_attack_for(k)] = true
		def_set[EnemyData.base_defense_for(k)] = true
	assert_gt(hp_set.size(), 1, "boss kinds must not share a single base hp")
	assert_gt(atk_set.size(), 1, "boss kinds must not share a single base attack")
	assert_gt(def_set.size(), 1, "boss kinds must not share a single base defense")

func test_boss_kinds_default_is_boss_false():
	# Same contract as the 5 legacy kinds — make_new mints a generic enemy; the
	# spawn layer flips is_boss for the boss room only.
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		var e := EnemyData.make_new(k)
		assert_false(e.is_boss, "kind %d should default is_boss=false" % k)

# --- Issue #421: EnemyData debuff/DOT tracker (isolated status-effect module) ---

func _fresh_enemy_20hp() -> EnemyData:
	var e := EnemyData.new()
	e.hp = 20
	e.max_hp = 20
	e.defense = 10
	return e

func test_dot_tick_deals_damage_per_second():
	var e := _fresh_enemy_20hp()
	e.apply_dot(4, 5.0)
	e.tick_dots(1.0)
	assert_eq(e.hp, 16, "one full second of a 4/tick DOT should deal 4 damage")

func test_dot_stops_after_duration_and_total_matches_expected():
	var e := _fresh_enemy_20hp()
	e.apply_dot(4, 5.0)
	for i in range(5):
		e.tick_dots(1.0)
	assert_eq(e.hp, 0, "4/tick over 5s should deal 20 total damage")
	# One more tick past expiry must not deal further damage.
	e.hp = 20
	e.tick_dots(1.0)
	assert_eq(e.hp, 20, "DOT must not apply damage once expired")

func test_debuff_applies_immediately_and_reverts_at_duration_boundary():
	var e := _fresh_enemy_20hp()
	e.apply_debuff("defense", 4, 10.0)
	assert_eq(e.defense, 6, "debuff should immediately subtract from the stat")
	e.tick_debuffs(10.0)
	assert_eq(e.defense, 10, "debuff must revert once its duration fully elapses")

func test_debuff_stays_active_across_small_sub_duration_ticks():
	var e := _fresh_enemy_20hp()
	e.apply_debuff("defense", 4, 10.0)
	for i in range(50):
		e.tick_debuffs(0.1)
	assert_eq(e.defense, 6, "50 x 0.1s ticks (5s total) must leave the 10s debuff still active")

# --- PRD #518 / issue #535: per-boss stat profiles ---

func test_every_boss_kind_declares_its_own_max_hp():
	# Core wiring: no boss may still fall through to the generic 8 hp
	# fallback. A boss returning the baseline means base_max_hp_for has no
	# case for it, which is exactly the bug this slice closes.
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		assert_ne(EnemyData.base_max_hp_for(k), _GENERIC_FALLBACK_MAX_HP,
			"boss kind %d still uses the generic fallback hp" % k)

# Per-boss profiles from the PRD #518 boss loadout table: [max_hp, attack, defense].
# Roles drive the numbers — melee-denial bruisers (Buster, Warden) are tanky,
# the kiting/ranged boss (Pearl) is squishiest, and the shielded boss (Bouncer)
# carries the roster's defense. Pinned so a tuning pass is a deliberate edit.
const _BOSS_PROFILES := {
	EnemyData.EnemyKind.SIR_PICKLETON: [7, 4, 0],
	EnemyData.EnemyKind.OLD_LADY_PEARL: [6, 2, 0],
	EnemyData.EnemyKind.TRASH_PANDA_TYRONE: [7, 3, 0],
	EnemyData.EnemyKind.BIG_BRUISER_BUSTER: [14, 4, 0],
	EnemyData.EnemyKind.LAST_CALL_LARRY: [10, 3, 0],
	EnemyData.EnemyKind.THE_BOUNCER: [12, 3, 1],
	EnemyData.EnemyKind.DJ_DUBSTEP: [9, 4, 0],
	EnemyData.EnemyKind.KARAOKE_KAREN: [9, 3, 0],
	EnemyData.EnemyKind.WARDEN_WRETCHED: [13, 4, 0],
}

func _assert_boss_profile(k: int) -> void:
	var p: Array = _BOSS_PROFILES[k]
	var n := EnemyData.display_name_for(k)
	assert_eq(EnemyData.base_max_hp_for(k), p[0], "%s max_hp" % n)
	assert_eq(EnemyData.base_attack_for(k), p[1], "%s attack" % n)
	assert_eq(EnemyData.base_defense_for(k), p[2], "%s defense" % n)

func test_sir_pickleton_profile_is_a_fragile_assassin():
	# Ambush/petrify + telegraphed charge: hits hard out of stealth, folds fast.
	_assert_boss_profile(EnemyData.EnemyKind.SIR_PICKLETON)

func test_old_lady_pearl_profile_is_a_fragile_kiter():
	# Summon adds + retreat and fire: the adds carry the fight, she does not.
	_assert_boss_profile(EnemyData.EnemyKind.OLD_LADY_PEARL)

func test_trash_panda_tyrone_profile_is_an_evasive_skirmisher():
	# Steal + zone denial: survives by running, not by soaking.
	_assert_boss_profile(EnemyData.EnemyKind.TRASH_PANDA_TYRONE)

func test_big_bruiser_buster_profile_is_a_melee_denial_bruiser():
	# Ground slam + knockback shove: the roster's beefiest melee wall.
	_assert_boss_profile(EnemyData.EnemyKind.BIG_BRUISER_BUSTER)

func test_last_call_larry_profile_is_a_midweight_zoner():
	# Zone denial + enrage: average bulk, the enrage supplies the spike.
	_assert_boss_profile(EnemyData.EnemyKind.LAST_CALL_LARRY)

func test_the_bouncer_profile_carries_the_defense():
	# Shielded front + knockback shove: armor is his identity.
	_assert_boss_profile(EnemyData.EnemyKind.THE_BOUNCER)

func test_dj_dubstep_profile_is_a_midweight_burster():
	# Ground slam on a beat + enrage: rhythm damage, thin armor.
	_assert_boss_profile(EnemyData.EnemyKind.DJ_DUBSTEP)

func test_karaoke_karen_profile_is_a_midweight_zone_caster():
	# Cone spray + summon adds: pressures space rather than trading blows.
	_assert_boss_profile(EnemyData.EnemyKind.KARAOKE_KAREN)

func test_warden_wretched_profile_is_a_tanky_trapper():
	# Pull + zone denial: drags you in and outlasts you.
	_assert_boss_profile(EnemyData.EnemyKind.WARDEN_WRETCHED)

func test_every_boss_kind_has_a_capped_detection_radius():
	# Iterates the enum rather than a hand-listed roster so a boss kind added
	# later cannot slip past the viewport-half-height ceiling. A radius above
	# DETECTION_RADIUS_MAX_PX would let a boss aggro from off-screen (#260).
	var max_px := EnemyData.DETECTION_RADIUS_MAX_PX
	for k in EnemyData.EnemyKind.values():
		var r: float = EnemyData.base_detection_radius_for(k)
		assert_gt(r, 0.0, "%s must have a positive detection radius" % EnemyData.display_name_for(k))
		assert_lte(r, max_px, "%s radius %f exceeds the viewport ceiling" % [EnemyData.display_name_for(k), r])

func test_boss_detection_radii_match_their_archetypes():
	# Pinned per-boss radii. Ranged/pull bosses open at the ceiling; brawlers
	# who want you in melee sit tight and see less.
	var expected := {
		EnemyData.EnemyKind.SIR_PICKLETON: 120.0,
		EnemyData.EnemyKind.OLD_LADY_PEARL: 135.0,
		EnemyData.EnemyKind.TRASH_PANDA_TYRONE: 130.0,
		EnemyData.EnemyKind.BIG_BRUISER_BUSTER: 90.0,
		EnemyData.EnemyKind.LAST_CALL_LARRY: 100.0,
		EnemyData.EnemyKind.THE_BOUNCER: 95.0,
		EnemyData.EnemyKind.DJ_DUBSTEP: 110.0,
		EnemyData.EnemyKind.KARAOKE_KAREN: 125.0,
		EnemyData.EnemyKind.WARDEN_WRETCHED: 135.0,
	}
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		assert_eq(EnemyData.base_detection_radius_for(k), expected[k], "%s detection radius" % entry[1])

func test_shielded_boss_has_the_rosters_highest_defense():
	# Design intent, not a literal: The Bouncer's shielded-front loadout means
	# armor is his identity, so no other boss may match or beat his defense.
	var bouncer := EnemyData.base_defense_for(EnemyData.EnemyKind.THE_BOUNCER)
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		if k == EnemyData.EnemyKind.THE_BOUNCER:
			continue
		assert_lt(EnemyData.base_defense_for(k), bouncer,
			"%s must not match the shielded boss's defense" % entry[1])

func test_kiting_boss_is_squishier_than_the_melee_denial_boss():
	# Old Lady Pearl retreats and fires; Big Bruiser Buster slams and shoves
	# anyone who closes. The ranged boss must be the softer target.
	assert_lt(
		EnemyData.base_max_hp_for(EnemyData.EnemyKind.OLD_LADY_PEARL),
		EnemyData.base_max_hp_for(EnemyData.EnemyKind.BIG_BRUISER_BUSTER),
		"the kiting boss must have less hp than the melee-denial boss")

func test_kiting_boss_outranges_the_melee_denial_boss():
	assert_gt(
		EnemyData.base_detection_radius_for(EnemyData.EnemyKind.OLD_LADY_PEARL),
		EnemyData.base_detection_radius_for(EnemyData.EnemyKind.BIG_BRUISER_BUSTER),
		"the kiting boss must notice the player from further out")

func test_standard_mob_profiles_are_untouched_by_the_boss_pass():
	# Regression guard for issue #535. BossRoster maps floor 1's Vacuum onto
	# EnemyKind.ROGUE_ROOMBA, which is also a standard mob kind — so giving the
	# bosses profiles is one edit away from silently retuning the roomba that
	# spawns in ordinary rooms. These are the pre-#535 values, verbatim.
	var expected := {
		EnemyData.EnemyKind.ANGRY_PIGEON: [6, 2, 0, 80.0],
		EnemyData.EnemyKind.ROGUE_ROOMBA: [12, 3, 0, 90.0],
		EnemyData.EnemyKind.DOG_KNIGHT: [24, 4, 2, 135.0],
		EnemyData.EnemyKind.CATNIP_DEALER: [14, 3, 0, 75.0],
		EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE: [10, 4, 0, 75.0],
	}
	for k in _NEW_KINDS:
		var p: Array = expected[k]
		var n := EnemyData.display_name_for(k)
		assert_eq(EnemyData.base_max_hp_for(k), p[0], "%s max_hp must be unchanged" % n)
		assert_eq(EnemyData.base_attack_for(k), p[1], "%s attack must be unchanged" % n)
		assert_eq(EnemyData.base_defense_for(k), p[2], "%s defense must be unchanged" % n)
		assert_eq(EnemyData.base_detection_radius_for(k), p[3], "%s detection radius must be unchanged" % n)

func test_make_new_is_well_formed_for_every_kind():
	# Edge cases across the full enum: a freshly minted enemy of any kind
	# starts at full health with a readable name, so a boss profile added
	# without a display name or with a zero hp typo fails here.
	for k in EnemyData.EnemyKind.values():
		var e := EnemyData.make_new(k)
		assert_gt(e.max_hp, 0, "kind %d must have positive max_hp" % k)
		assert_eq(e.hp, e.max_hp, "kind %d must spawn at full health" % k)
		assert_ne(e.enemy_name, "", "kind %d must have a display name" % k)
		assert_eq(e.detection_radius, EnemyData.base_detection_radius_for(k), "kind %d radius" % k)

func test_boss_base_defense_stays_under_the_dog_knights():
	# The Dog Knight is the armored outlier of the whole enum (issue #163),
	# and BossScaling triples boss defense on top of these values — so a boss
	# base defense at or above 2 would both break that contract and turn the
	# fight into a chip-damage slog under DamageResolver's subtractive
	# mitigation. Boss bulk belongs in HP, armor belongs to The Bouncer.
	var dog_knight := EnemyData.base_defense_for(EnemyData.EnemyKind.DOG_KNIGHT)
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		assert_lt(EnemyData.base_defense_for(k), dog_knight,
			"%s base defense must stay under the Dog Knight's" % entry[1])
