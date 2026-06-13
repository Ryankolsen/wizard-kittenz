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

func test_boss_kinds_share_boss_base_stats():
	# Sprite-only differentiation per PRD: all 9 new kinds must collapse to a
	# single value for hp/attack/defense. Set size 1 across the cohort proves it.
	var hp_set := {}
	var atk_set := {}
	var def_set := {}
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		hp_set[EnemyData.base_max_hp_for(k)] = true
		atk_set[EnemyData.base_attack_for(k)] = true
		def_set[EnemyData.base_defense_for(k)] = true
	assert_eq(hp_set.size(), 1, "boss kinds must share base hp")
	assert_eq(atk_set.size(), 1, "boss kinds must share base attack")
	assert_eq(def_set.size(), 1, "boss kinds must share base defense")

func test_boss_kinds_default_is_boss_false():
	# Same contract as the 5 legacy kinds — make_new mints a generic enemy; the
	# spawn layer flips is_boss for the boss room only.
	for entry in _BOSS_KINDS_AND_NAMES:
		var k: int = entry[0]
		var e := EnemyData.make_new(k)
		assert_false(e.is_boss, "kind %d should default is_boss=false" % k)
