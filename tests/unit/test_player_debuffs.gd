extends GutTest

# Issue #160. Mirrors test_powerups.gd shape — duck-typed CharacterData target,
# PowerUpManager drives ticking via apply_effect (the debuff entry point).

func _new_data() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Test")

# --- Issue tests ---

func test_wet_effect_reduces_speed_by_30_percent_and_restores():
	# Issue test 1.
	var c := _new_data()
	var base_speed := c.speed
	var effect := WetEffect.new()
	effect.apply_to(c)
	assert_almost_eq(c.speed, base_speed * 0.70, 0.001, "wet applies -30% speed")
	effect.remove()
	assert_almost_eq(c.speed, base_speed, 0.001, "speed restored on remove")

func test_slowness_effect_reduces_speed_by_50_percent_and_restores():
	# Issue test 2.
	var c := _new_data()
	var base_speed := c.speed
	var effect := SlownessEffect.new()
	effect.apply_to(c)
	assert_almost_eq(c.speed, base_speed * 0.50, 0.001, "slowness applies -50% speed")
	effect.remove()
	assert_almost_eq(c.speed, base_speed, 0.001, "speed restored on remove")

func test_confusion_effect_sets_and_clears_flag():
	# Issue test 3.
	var c := _new_data()
	assert_false(c.is_confused(), "default not confused")
	var effect := ConfusionEffect.new()
	effect.apply_to(c)
	assert_true(c.is_confused(), "confusion active after apply")
	effect.remove()
	assert_false(c.is_confused(), "confusion cleared after remove")

func test_wet_expires_and_restores_speed_via_manager():
	# Issue test 4. Drives expiry through PowerUpManager (the same path
	# Player.apply_debuff uses).
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var effect := WetEffect.new(0.5)
	manager.apply_effect(effect, c)
	manager.tick(0.6)
	assert_true(effect.is_expired(), "wet expired after duration elapsed")
	assert_false(manager.is_active(WetEffect.TYPE), "wet removed from active set")
	assert_almost_eq(c.speed, base_speed, 0.001, "speed back to base after expiry")

func test_wet_re_apply_refreshes_duration_not_magnitude():
	# Issue test 5. After draining 2.0 of 3.0, re-applying should reset
	# remaining to full duration; speed delta stays at one -30% bite.
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var first := manager.apply_effect(WetEffect.new(3.0), c)
	manager.tick(2.0)
	assert_lt(first.remaining, 3.0, "first instance drained by tick")
	var second := manager.apply_effect(WetEffect.new(3.0), c)
	assert_eq(second, first, "same effect refreshed, not replaced")
	assert_almost_eq(first.remaining, 3.0, 0.001, "remaining reset to full")
	assert_almost_eq(c.speed, base_speed * 0.70, 0.001, "magnitude does not stack on refresh")

func test_wet_and_slowness_coexist_and_partially_expire():
	# Issue test 6. Two distinct debuffs both active; combined speed reflects
	# both reductions; expiring one leaves the other intact.
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	# Apply wet first (-30% of base) then slowness (-50% of post-wet). Order
	# matters for the exact combined value because each computes its delta
	# off the live target.speed at apply time — same as how CatnipEffect
	# stacks against any other multiplicative buff in the system.
	manager.apply_effect(WetEffect.new(0.5), c)
	var post_wet := c.speed
	assert_almost_eq(post_wet, base_speed * 0.70, 0.001, "wet alone is -30%")
	manager.apply_effect(SlownessEffect.new(2.0), c)
	var both := c.speed
	assert_almost_eq(both, post_wet * 0.50, 0.001, "slowness stacks on top of wet")
	assert_true(manager.is_active(WetEffect.TYPE))
	assert_true(manager.is_active(SlownessEffect.TYPE))
	# Expire wet only.
	manager.tick(0.6)
	assert_false(manager.is_active(WetEffect.TYPE), "wet expired")
	assert_true(manager.is_active(SlownessEffect.TYPE), "slowness still active")
	# Speed reflects only the slowness delta now. Wet on remove added back the
	# 30% it had subtracted from `post_wet`, so c.speed = post_wet - slowness_delta + wet_delta.
	# Concretely: post_wet = 42, slowness_delta = 21 (50% of 42), wet_delta = 18 (30% of 60).
	# Remaining speed = 42 - 21 + 18 = 39. (Not base_speed * 0.5 because slowness's
	# delta was captured at the post-wet target value.)
	var slowness_delta: float = post_wet * 0.50
	var wet_delta: float = base_speed * 0.30
	var expected: float = post_wet - slowness_delta + wet_delta
	assert_almost_eq(c.speed, expected, 0.001, "remaining speed reflects only the slowness delta")

# --- Coverage extras ---

func test_apply_effect_unknown_null_returns_null_no_mutation():
	var c := _new_data()
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var ret := manager.apply_effect(null, c)
	assert_null(ret)
	assert_eq(c.speed, base_speed, "null effect does not touch speed")
	assert_eq(manager.active_count(), 0)

func test_confusion_counter_handles_double_apply_and_remove():
	# The counter (not bool) guards against a second source clearing the
	# flag prematurely when only one expires.
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
