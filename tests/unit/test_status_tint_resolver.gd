extends GutTest

# Status tint resolver (PRD #518 / issue #536). Pure function mapping the set
# of active player-effect ids to a single colour with priority ordering:
# petrify > wet > slowness. Extracted from the old wet-specific routine in
# Player._apply_wet_tint, which forced every other state back to white — this
# module is what stops the next status effect from being another branch
# fighting over `modulate`.

func test_no_active_effects_resolves_to_white():
	assert_eq(StatusTintResolver.resolve([]), Color.WHITE,
		"no active effects should resolve to white")


func test_petrify_outranks_wet_and_slowness():
	assert_eq(StatusTintResolver.resolve([PowerUpEffect.TYPE_PETRIFY]),
		StatusTintResolver.PETRIFY_TINT, "petrify alone should resolve to stone-grey")
	assert_eq(StatusTintResolver.resolve([PowerUpEffect.TYPE_WET]),
		StatusTintResolver.WET_TINT, "wet alone should resolve to the existing blue")
	assert_eq(
		StatusTintResolver.resolve([PowerUpEffect.TYPE_PETRIFY, PowerUpEffect.TYPE_WET]),
		StatusTintResolver.PETRIFY_TINT,
		"petrify plus wet should resolve to stone-grey, not blue — the clobbering bug as an assertion")


func test_wet_outranks_slowness():
	assert_eq(
		StatusTintResolver.resolve([PowerUpEffect.TYPE_SLOWNESS, PowerUpEffect.TYPE_WET]),
		StatusTintResolver.WET_TINT,
		"wet should outrank slowness regardless of set order")


func test_unknown_effect_id_resolves_to_white_without_crashing():
	assert_eq(StatusTintResolver.resolve(["not_a_real_effect"]), Color.WHITE,
		"an unknown effect id should resolve to white without crashing")


func test_empty_effect_set_resolves_to_white_without_crashing():
	assert_eq(StatusTintResolver.resolve([]), Color.WHITE,
		"an empty effect set should resolve to white without crashing")
