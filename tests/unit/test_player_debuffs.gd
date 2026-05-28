extends GutTest

# Issue #160 + PRD #284 Slice 2. Debuffs now flow through the single
# PowerUpManager.apply(type_id, target, duration) entry — the same path
# Player.apply_debuff routes (type_id, duration) descriptions through.

func _new_data() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Test")

# --- Effect-class internals (still valid: covers apply_to/remove math) ---

func test_wet_effect_reduces_speed_by_30_percent_and_restores():
	var c := _new_data()
	var base_speed := c.speed
	var effect := WetEffect.new()
	effect.apply_to(c)
	assert_almost_eq(c.speed, base_speed * 0.70, 0.001, "wet applies -30% speed")
	effect.remove()
	assert_almost_eq(c.speed, base_speed, 0.001, "speed restored on remove")

func test_slowness_effect_reduces_speed_by_50_percent_and_restores():
	var c := _new_data()
	var base_speed := c.speed
	var effect := SlownessEffect.new()
	effect.apply_to(c)
	assert_almost_eq(c.speed, base_speed * 0.50, 0.001, "slowness applies -50% speed")
	effect.remove()
	assert_almost_eq(c.speed, base_speed, 0.001, "speed restored on remove")

func test_confusion_effect_sets_and_clears_flag():
	var c := _new_data()
	assert_false(c.is_confused(), "default not confused")
	var effect := ConfusionEffect.new()
	effect.apply_to(c)
	assert_true(c.is_confused(), "confusion active after apply")
	effect.remove()
	assert_false(c.is_confused(), "confusion cleared after remove")

# --- Unified apply path (PRD #284 Slice 2) ---

func test_wet_expires_and_restores_speed_via_unified_apply():
	# Slice 2 test 1 — manager.apply("wet", c, 0.5) reduces speed by 30% and
	# expires after the caller-tuned duration. Routes through the same factory
	# the pickup path uses.
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var effect := manager.apply("wet", c, 0.5)
	assert_not_null(effect, "apply returns the active effect")
	assert_true(effect is WetEffect, "apply dispatched WetEffect")
	assert_almost_eq(c.speed, base_speed * 0.70, 0.001, "wet applies -30% speed")
	manager.tick(0.6)
	assert_true(effect.is_expired(), "wet expired after caller-tuned duration elapsed")
	assert_false(manager.is_active(WetEffect.TYPE), "wet removed from active set")
	assert_almost_eq(c.speed, base_speed, 0.001, "speed back to base after expiry")

func test_wet_re_apply_refreshes_duration_not_magnitude():
	# Slice 2 test 3 — refresh-not-stack on the unified path.
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var first := manager.apply("wet", c, 3.0)
	manager.tick(2.0)
	assert_lt(first.remaining, 3.0, "first instance drained by tick")
	var second := manager.apply("wet", c, 3.0)
	assert_eq(second, first, "same effect refreshed, not replaced")
	assert_almost_eq(first.remaining, 3.0, 0.001, "remaining reset to full")
	assert_almost_eq(c.speed, base_speed * 0.70, 0.001, "magnitude does not stack on refresh")

func test_slowness_expiry_reverts_exact_delta_preserving_external_change():
	# Slice 2 test 4 — only the slowness delta is removed; an external bump
	# during the buff survives expiry.
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	manager.apply("slowness", c, 0.5)
	var slowness_delta := base_speed - c.speed  # 50% of base
	c.speed += 7.0  # external mid-buff bump
	var pre_tick_speed := c.speed
	manager.tick(0.6)
	assert_false(manager.is_active(SlownessEffect.TYPE), "slowness expired")
	# Removed delta should be slowness_delta only — external +7 survives.
	assert_almost_eq(c.speed, pre_tick_speed + slowness_delta, 0.001,
		"only slowness delta reverted; external +7 survives")

func test_wet_and_slowness_coexist_and_partially_expire():
	# Two distinct debuff kinds both active via the unified apply; combined
	# speed reflects both reductions; expiring one leaves the other intact.
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	manager.apply("wet", c, 0.5)
	var post_wet := c.speed
	assert_almost_eq(post_wet, base_speed * 0.70, 0.001, "wet alone is -30%")
	manager.apply("slowness", c, 2.0)
	var both := c.speed
	assert_almost_eq(both, post_wet * 0.50, 0.001, "slowness stacks on top of wet")
	assert_true(manager.is_active(WetEffect.TYPE))
	assert_true(manager.is_active(SlownessEffect.TYPE))
	manager.tick(0.6)
	assert_false(manager.is_active(WetEffect.TYPE), "wet expired")
	assert_true(manager.is_active(SlownessEffect.TYPE), "slowness still active")
	var slowness_delta: float = post_wet * 0.50
	var wet_delta: float = base_speed * 0.30
	var expected: float = post_wet - slowness_delta + wet_delta
	assert_almost_eq(c.speed, expected, 0.001, "remaining speed reflects only the slowness delta")

# --- Coverage extras ---

func test_apply_unknown_id_returns_null_no_mutation():
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var ret := manager.apply("not_a_kind", c, 1.0)
	assert_null(ret)
	assert_eq(c.speed, base_speed, "unknown id does not touch speed")
	assert_eq(manager.active_count(), 0)

func test_apply_effect_removed_from_manager():
	# Slice 2 test 6 — apply_effect is retired; only apply remains.
	var manager := PowerUpManager.new()
	assert_false(manager.has_method("apply_effect"),
		"apply_effect should be removed; unified apply is the only entry")

func test_confusion_counter_handles_double_apply_and_remove():
	# Slice 2 test 7 — counter guard on the target survives two sources +
	# partial removal. A single PowerUpManager refreshes-not-stacks, so this
	# tests the underlying CharacterData counter math directly (the layer the
	# unified apply path delegates to via ConfusionEffect.apply_to). Production
	# parallel: two enemies each pushing confusion via their own seam would
	# both land on the same player counter.
	var c := _new_data()
	var a := ConfusionEffect.new()
	var b := ConfusionEffect.new()
	a.apply_to(c)
	b.apply_to(c)
	assert_true(c.is_confused())
	a.remove()
	assert_true(c.is_confused(), "one source removed, other still active")
	b.remove()
	assert_false(c.is_confused(), "all sources removed clears the flag")
