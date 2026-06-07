extends GutTest

# Slice 7 of PRD #358. PotionSlotState.derive(slot_def, count, cooldown_fraction)
# is the pure helper that drives the belt HUD's per-slot render — extracted so
# the empty / disabled / cooldown_fraction / uses_texture / reason decisions
# are testable without instancing a Control tree. Mirrors QuickbarSlotState.

func _def_with_icon() -> PotionDefinition:
	var tex := ImageTexture.new()
	return PotionDefinition.make(
		"hp", "Health Potion", "",
		PotionDefinition.EffectKind.HEAL_PERCENT, 50, 0.0, "healing", tex)

func _def_no_icon() -> PotionDefinition:
	# Built directly (not via the catalog, which now seeds icons) so the
	# no-art placeholder path stays covered.
	return PotionDefinition.make(
		"hp_no_icon", "Health Potion", "",
		PotionDefinition.EffectKind.HEAL_PERCENT, 50, 0.0, "healing")

func test_empty_slot_state_is_empty_disabled():
	var state := PotionSlotState.derive(null, 0, 0.0)
	assert_true(state["empty"], "empty slot must report empty=true")
	assert_true(state["disabled"], "empty slot must be disabled")
	assert_eq(state["reason"], PotionSlotState.REASON_EMPTY)

func test_ready_slot_surfaces_count_and_texture_flag():
	var d := _def_with_icon()
	var state := PotionSlotState.derive(d, 5, 0.0)
	assert_false(state["empty"])
	assert_false(state["disabled"])
	assert_eq(state["count"], 5)
	assert_true(state["uses_texture"], "def with icon must report uses_texture true")
	assert_eq(state["reason"], PotionSlotState.REASON_READY)

func test_cooldown_disables_and_reports_fraction():
	var d := _def_with_icon()
	var state := PotionSlotState.derive(d, 5, 0.5)
	assert_true(state["disabled"], "cooldown must be disabled")
	assert_almost_eq(state["cooldown_fraction"], 0.5, 0.01)
	assert_eq(state["reason"], PotionSlotState.REASON_COOLDOWN)

func test_zero_count_disables_with_out_of_stock_reason():
	var d := _def_with_icon()
	var state := PotionSlotState.derive(d, 0, 0.0)
	assert_false(state["empty"], "0-count slot still has a def, not empty")
	assert_true(state["disabled"])
	assert_eq(state["count"], 0)
	assert_eq(state["reason"], PotionSlotState.REASON_OUT_OF_STOCK)

func test_def_without_icon_reports_uses_texture_false():
	var d := _def_no_icon()
	var state := PotionSlotState.derive(d, 3, 0.0)
	assert_false(state["uses_texture"], "def without icon falls back to placeholder")
