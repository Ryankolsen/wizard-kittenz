extends GutTest

# Tests for the declarative power-up registry behind PowerUpEffect.make().
# The registry is the single source of truth for all six effect kinds —
# catnip, ale, mushrooms, wet, slowness, confusion — including class,
# default duration, and is_pickup classification. This slice is purely
# additive: existing call sites and tests must keep working unchanged.

const ALL_IDS := ["catnip", "ale", "mushrooms", "wet", "slowness", "confusion"]
const EXPECTED_DEFAULTS := {
	"catnip": 8.0,
	"ale": 10.0,
	"mushrooms": 6.0,
	"wet": 4.0,
	"slowness": 3.0,
	"confusion": 3.0,
}
const EXPECTED_PICKUPS := {
	"catnip": true,
	"ale": true,
	"mushrooms": true,
	"wet": false,
	"slowness": false,
	"confusion": false,
}

func test_registry_totality_make_returns_correct_class_for_every_kind():
	# Registry totality: every declared kind constructs via the factory and
	# is of the expected concrete class. This is the gap-closer — today
	# make("wet"/"slowness"/"confusion") returns null.
	assert_true(PowerUpEffect.make("catnip") is CatnipEffect, "catnip -> CatnipEffect")
	assert_true(PowerUpEffect.make("ale") is AleEffect, "ale -> AleEffect")
	assert_true(PowerUpEffect.make("mushrooms") is MushroomEffect, "mushrooms -> MushroomEffect")
	assert_true(PowerUpEffect.make("wet") is WetEffect, "wet -> WetEffect")
	assert_true(PowerUpEffect.make("slowness") is SlownessEffect, "slowness -> SlownessEffect")
	assert_true(PowerUpEffect.make("confusion") is ConfusionEffect, "confusion -> ConfusionEffect")

func test_default_durations_match_documented_values():
	for id in ALL_IDS:
		var effect: PowerUpEffect = PowerUpEffect.make(id)
		assert_not_null(effect, "kind %s should be constructible" % id)
		assert_almost_eq(effect.duration, float(EXPECTED_DEFAULTS[id]), 0.001,
			"default duration for %s" % id)

func test_explicit_duration_override_for_pickup_and_debuff_kinds():
	var wet := PowerUpEffect.make("wet", 7.5)
	assert_not_null(wet)
	assert_almost_eq(wet.duration, 7.5, 0.001, "wet duration override")
	var catnip := PowerUpEffect.make("catnip", 2.0)
	assert_not_null(catnip)
	assert_almost_eq(catnip.duration, 2.0, 0.001, "catnip duration override")

func test_unknown_id_returns_null_with_and_without_duration():
	assert_null(PowerUpEffect.make("not_a_powerup"),
		"unknown id without duration is null (late-gate preserved)")
	assert_null(PowerUpEffect.make("not_a_powerup", 5.0),
		"duration arg does not bypass unknown-id guard")

func test_is_pickup_classification_for_every_kind():
	for id in ALL_IDS:
		assert_eq(PowerUpEffect.is_pickup(id), bool(EXPECTED_PICKUPS[id]),
			"is_pickup(%s)" % id)
