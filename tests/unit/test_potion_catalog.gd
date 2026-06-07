extends GutTest

# Slice 1 (issue #359). Pure-data catalog of potion definitions — single source
# of truth for every later potion-system slice. Mirrors SkillTree's static
# factory + find() pattern.

func test_catalog_exposes_three_seeded_potions():
	assert_eq(PotionCatalog.all().size(), 3)
	assert_not_null(PotionCatalog.find("health_potion"))

func test_health_potion_definition_fields():
	var def := PotionCatalog.find("health_potion")
	assert_eq(def.effect_kind, PotionDefinition.EffectKind.HEAL_PERCENT)
	assert_eq(def.magnitude, 50)
	assert_eq(def.duration, 0.0)
	# Icon defaults to null until art lands (slice 7/8 wires the belt HUD).
	assert_null(def.icon)

func test_find_unknown_id_returns_null():
	assert_null(PotionCatalog.find("nope"))
