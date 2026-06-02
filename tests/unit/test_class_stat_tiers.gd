extends GutTest

# PRD #316 tier table — single source of truth mirrored from the issue.
# Each row is [stat, battle_tier, wizard_tier, sleepy_tier, chonk_tier].
const _TABLE := [
	["max_hp",            "SECONDARY", "OFF_STAT", "SECONDARY", "PRIMARY"],
	["max_mp",            "OFF_STAT",  "PRIMARY",  "PRIMARY",   "FORBIDDEN"],
	["attack",            "PRIMARY",   "FORBIDDEN","OFF_STAT",  "SECONDARY"],
	["magic_attack",      "OFF_STAT",  "PRIMARY",  "SECONDARY", "FORBIDDEN"],
	["defense",           "SECONDARY", "OFF_STAT", "OFF_STAT",  "PRIMARY"],
	["magic_resistance",  "OFF_STAT",  "SECONDARY","SECONDARY", "SECONDARY"],
	["speed",             "SECONDARY", "SECONDARY","OFF_STAT",  "OFF_STAT"],
	["dexterity",         "PRIMARY",   "OFF_STAT", "OFF_STAT",  "SECONDARY"],
	["evasion",           "SECONDARY", "OFF_STAT", "OFF_STAT",  "FORBIDDEN"],
	["crit_chance",       "PRIMARY",   "SECONDARY","OFF_STAT",  "OFF_STAT"],
	["luck",              "SECONDARY", "SECONDARY","SECONDARY", "OFF_STAT"],
	["regeneration",      "OFF_STAT",  "OFF_STAT", "PRIMARY",   "SECONDARY"],
	["mp_regen",          "FORBIDDEN", "SECONDARY","PRIMARY",   "FORBIDDEN"],
]

const _CLASSES := [
	CharacterData.CharacterClass.BATTLE_KITTEN,
	CharacterData.CharacterClass.WIZARD_KITTEN,
	CharacterData.CharacterClass.SLEEPY_KITTEN,
	CharacterData.CharacterClass.CHONK_KITTEN,
]

func _tier_of(name: String) -> int:
	match name:
		"PRIMARY": return ClassStatTiers.Tier.PRIMARY
		"SECONDARY": return ClassStatTiers.Tier.SECONDARY
		"OFF_STAT": return ClassStatTiers.Tier.OFF_STAT
	return ClassStatTiers.Tier.FORBIDDEN

func test_tier_table_matches_prd_for_all_classes_and_stats():
	for row in _TABLE:
		var stat: String = row[0]
		for i in 4:
			var klass: int = _CLASSES[i]
			var expected: int = _tier_of(row[i + 1])
			var actual: int = ClassStatTiers.get_tier(klass, stat)
			assert_eq(actual, expected,
				"tier mismatch for %s / %s" % [CharacterData.CharacterClass.keys()[klass - 6], stat])

func test_sp_cost_one_for_primary_and_secondary_two_for_off_stat():
	for row in _TABLE:
		var stat: String = row[0]
		for i in 4:
			var klass: int = _CLASSES[i]
			var tier_name: String = row[i + 1]
			var cost: int = ClassStatTiers.get_sp_cost(klass, stat)
			match tier_name:
				"PRIMARY", "SECONDARY":
					assert_eq(cost, 1, "%s/%s expected cost 1" % [tier_name, stat])
				"OFF_STAT":
					assert_eq(cost, 2, "%s/%s expected cost 2" % [tier_name, stat])
				"FORBIDDEN":
					assert_eq(cost, 0, "%s/%s expected cost 0" % [tier_name, stat])

func test_caps_match_prd_per_tier():
	for row in _TABLE:
		var stat: String = row[0]
		for i in 4:
			var klass: int = _CLASSES[i]
			var tier_name: String = row[i + 1]
			var cap: int = ClassStatTiers.get_cap(klass, stat)
			match tier_name:
				"PRIMARY":
					if klass == CharacterData.CharacterClass.SLEEPY_KITTEN and stat == "regeneration":
						assert_eq(cap, ClassStatTiers.SLEEPY_REGEN_CAP, "sleepy regen Primary cap is 5")
					else:
						assert_eq(cap, ClassStatTiers.PRIMARY_UNCAPPED, "%s/%s Primary uncapped" % [tier_name, stat])
				"SECONDARY":
					assert_eq(cap, ClassStatTiers.SECONDARY_CAP, "Secondary cap is 10")
				"OFF_STAT":
					assert_eq(cap, ClassStatTiers.OFF_STAT_CAP, "Off-stat cap is 3")
				"FORBIDDEN":
					assert_eq(cap, 0, "Forbidden cap is 0")

func test_cat_tier_inherits_kitten_archetype_tiers():
	var pairs := [
		[CharacterData.CharacterClass.BATTLE_KITTEN, CharacterData.CharacterClass.BATTLE_CAT],
		[CharacterData.CharacterClass.WIZARD_KITTEN, CharacterData.CharacterClass.WIZARD_CAT],
		[CharacterData.CharacterClass.SLEEPY_KITTEN, CharacterData.CharacterClass.SLEEPY_CAT],
		[CharacterData.CharacterClass.CHONK_KITTEN, CharacterData.CharacterClass.CHONK_CAT],
	]
	for row in _TABLE:
		var stat: String = row[0]
		for pair in pairs:
			assert_eq(ClassStatTiers.get_tier(pair[1], stat),
					  ClassStatTiers.get_tier(pair[0], stat),
					  "Cat tier should mirror Kitten for %s" % stat)

func test_unknown_stat_is_forbidden():
	var t := ClassStatTiers.get_tier(CharacterData.CharacterClass.BATTLE_KITTEN, "nonsense")
	assert_eq(t, ClassStatTiers.Tier.FORBIDDEN)
