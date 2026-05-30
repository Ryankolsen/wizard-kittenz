extends GutTest

const _NEW_KINDS := [
	EnemyData.EnemyKind.ANGRY_PIGEON,
	EnemyData.EnemyKind.ROGUE_ROOMBA,
	EnemyData.EnemyKind.DOG_KNIGHT,
	EnemyData.EnemyKind.CATNIP_DEALER,
	EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE,
]

func test_make_new_angry_pigeon_has_expected_defaults():
	var e := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_eq(e.kind, EnemyData.EnemyKind.ANGRY_PIGEON)
	assert_eq(e.enemy_name, "Angry Pigeon")
	assert_eq(e.max_hp, 4)
	assert_eq(e.hp, 4)
	assert_eq(e.attack, 1)
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

func test_all_kinds_share_equal_base_stats():
	# PRD #151 phase 1: all 5 kinds use the same base stats; differentiation
	# is a future PRD. If a future change reintroduces per-kind stats this
	# test fails fast and the maintainer can update the contract.
	var hp_set := {}
	var atk_set := {}
	var def_set := {}
	var xp_set := {}
	var gold_set := {}
	for k in _NEW_KINDS:
		hp_set[EnemyData.base_max_hp_for(k)] = true
		atk_set[EnemyData.base_attack_for(k)] = true
		# DOG_KNIGHT (issue #163) is the documented exception to the equal-
		# stats rule — its raised defense is exercised by test_enemy_behavior.
		if k != EnemyData.EnemyKind.DOG_KNIGHT:
			def_set[EnemyData.base_defense_for(k)] = true
		xp_set[EnemyData.base_xp_for(k)] = true
		gold_set[EnemyData.base_gold_for(k)] = true
	assert_eq(hp_set.size(), 1, "all kinds must share base hp")
	assert_eq(atk_set.size(), 1, "all kinds must share base attack")
	assert_eq(def_set.size(), 1, "non-DOG_KNIGHT kinds must share base defense")
	assert_eq(xp_set.size(), 1, "all kinds must share base xp")
	assert_eq(gold_set.size(), 1, "all kinds must share base gold")

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
	assert_eq(e.hp, 2)
	assert_eq(e.take_damage(99), 2, "overkill returns only damage actually dealt")
	assert_eq(e.hp, 0)
	assert_false(e.is_alive())

func test_make_new_returns_independent_instances():
	var a := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var b := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	a.take_damage(99)
	assert_eq(a.hp, 0)
	assert_eq(b.hp, 4, "second instance should be untouched")

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
