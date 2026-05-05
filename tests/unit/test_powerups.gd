extends GutTest

# --- Issue tests ---

func test_apply_catnip_increases_speed_by_50_percent():
	# Issue test 1: PowerUpManager.apply("catnip", kitten_stats) increases
	# kitten_stats.speed by 50%.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var effect := manager.apply("catnip", c)
	assert_not_null(effect, "apply returns the active effect")
	assert_almost_eq(c.speed, base_speed * 1.5, 0.001, "catnip applies +50% speed")
	assert_true(manager.is_active("catnip"))

func test_catnip_expires_and_returns_speed_to_base():
	# Issue test 2: after PowerUpManager.tick(duration) the speed modifier is
	# removed and speed returns to its base value.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var effect := manager.apply("catnip", c)
	manager.tick(effect.duration)
	assert_almost_eq(c.speed, base_speed, 0.001, "speed returns to baseline after expiry")
	assert_false(manager.is_active("catnip"), "expired effect removed from active set")

func test_catnip_refresh_resets_remaining_to_full_duration():
	# Issue test 3: applying catnip while catnip is already active resets the
	# remaining duration to the full duration (refresh, not stack).
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var base_speed := c.speed
	var manager := PowerUpManager.new()
	var first := manager.apply("catnip", c)
	manager.tick(5.0)
	assert_lt(first.remaining, first.duration, "duration drained by tick")

	var second := manager.apply("catnip", c)
	assert_eq(second, first, "same effect refreshed, not replaced")
	assert_almost_eq(first.remaining, first.duration, 0.001, "remaining reset to full")
	# Stack guard: speed is still exactly +50%, not +100%.
	assert_almost_eq(c.speed, base_speed * 1.5, 0.001, "refresh does not stack the bonus")

func test_ale_wobble_returns_nonzero_varying_offset():
	# Issue test 4: AleEffect.get_movement_offset(time) returns a non-zero
	# Vector2 that varies with time (sinusoidal).
	var v0 := AleEffect.get_movement_offset(0.0)
	# At t=0 the sin terms are zero, so the offset itself is zero — that's
	# not the assertion. Pick a non-zero time so the wobble is engaged.
	var v_quarter := AleEffect.get_movement_offset(0.25)
	var v_half := AleEffect.get_movement_offset(0.5)
	assert_eq(v0, Vector2.ZERO, "offset is zero at t=0 (sin baseline)")
	assert_ne(v_quarter, Vector2.ZERO, "wobble produces non-zero offset at t=0.25")
	assert_ne(v_quarter, v_half, "offset varies with time (sinusoidal)")

func test_mushroom_emits_random_spell_fired_once_per_2s_interval():
	# Issue test 5: MushroomEffect.tick(2.0) emits random_spell_fired exactly
	# once per 2-second interval.
	var effect := MushroomEffect.new()
	var calls := [0]
	effect.random_spell_fired.connect(func(): calls[0] += 1)
	effect.tick(2.0)
	assert_eq(calls[0], 1, "exactly one emission per 2s tick")

# --- Coverage extras ---

func test_ale_increases_attack_and_reverts_on_expiry():
	var c := CharacterData.make_new(CharacterData.CharacterClass.NINJA)  # attack 4
	var base_attack := c.attack
	var manager := PowerUpManager.new()
	var effect := manager.apply("ale", c)
	assert_gt(c.attack, base_attack, "ale increases attack")
	manager.tick(effect.duration)
	assert_eq(c.attack, base_attack, "attack returns to baseline after expiry")

func test_ale_minimum_one_attack_bonus_at_low_base():
	# Mage attack 2 * 0.30 = 0.6, rounded = 1; the floor ensures the bonus is
	# always meaningful even at low base attack.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	assert_eq(c.attack, 2)
	var manager := PowerUpManager.new()
	manager.apply("ale", c)
	assert_eq(c.attack, 3, "+1 floor applied to small base attack")

func test_unknown_powerup_id_returns_null_no_mutation():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var base_speed := c.speed
	var base_attack := c.attack
	var manager := PowerUpManager.new()
	var effect := manager.apply("not_a_powerup", c)
	assert_null(effect)
	assert_eq(c.speed, base_speed, "unknown id does not touch speed")
	assert_eq(c.attack, base_attack, "unknown id does not touch attack")
	assert_eq(manager.active_count(), 0)

func test_two_distinct_powerups_active_simultaneously():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var manager := PowerUpManager.new()
	manager.apply("catnip", c)
	manager.apply("ale", c)
	assert_true(manager.is_active("catnip"))
	assert_true(manager.is_active("ale"))
	assert_eq(manager.active_count(), 2, "distinct types coexist")

func test_partial_tick_does_not_expire_long_powerup():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var manager := PowerUpManager.new()
	manager.apply("ale", c)  # 10s duration
	manager.tick(5.0)
	assert_true(manager.is_active("ale"), "half-elapsed effect still active")

func test_mushroom_emits_three_times_over_full_duration():
	var effect := MushroomEffect.new()
	var calls := [0]
	effect.random_spell_fired.connect(func(): calls[0] += 1)
	effect.tick(2.0)
	effect.tick(2.0)
	effect.tick(2.0)
	assert_eq(calls[0], 3, "3 emissions over 6s duration")
	assert_true(effect.is_expired(), "expired after full duration")

func test_mushroom_does_not_emit_under_interval():
	var effect := MushroomEffect.new()
	var calls := [0]
	effect.random_spell_fired.connect(func(): calls[0] += 1)
	effect.tick(1.5)
	assert_eq(calls[0], 0, "no emission under 2s")
	effect.tick(0.5)
	assert_eq(calls[0], 1, "emission once accumulator reaches 2s")

func test_mushroom_large_tick_drains_multi_emission():
	# Defensive: a tick > FIRE_INTERVAL should emit once per interval drained,
	# not just once.
	var effect := MushroomEffect.new()
	var calls := [0]
	effect.random_spell_fired.connect(func(): calls[0] += 1)
	effect.tick(4.0)
	assert_eq(calls[0], 2, "tick(4.0) emits twice")

func test_powerup_factory_makes_correct_type():
	var catnip := PowerUpEffect.make("catnip")
	var ale := PowerUpEffect.make("ale")
	var mushrooms := PowerUpEffect.make("mushrooms")
	assert_true(catnip is CatnipEffect)
	assert_true(ale is AleEffect)
	assert_true(mushrooms is MushroomEffect)
	assert_null(PowerUpEffect.make("unknown"), "unknown id falls through to null")

func test_powerup_durations_match_spec():
	# Issue spec: catnip 8s, ale 10s, mushrooms 6s.
	assert_eq(CatnipEffect.DURATION, 8.0)
	assert_eq(AleEffect.DURATION, 10.0)
	assert_eq(MushroomEffect.DURATION, 6.0)

func test_zero_or_negative_tick_is_noop():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	var manager := PowerUpManager.new()
	var effect := manager.apply("catnip", c)
	var remaining_before := effect.remaining
	manager.tick(0.0)
	assert_eq(effect.remaining, remaining_before, "zero tick does nothing")
	manager.tick(-1.0)
	assert_eq(effect.remaining, remaining_before, "negative tick does nothing")

func test_powerup_revert_preserves_concurrent_speed_change():
	# If something external bumps speed during a buff (e.g., a future second
	# power-up), removing the catnip bonus should subtract only the delta we
	# applied — not snap back to the original pre-buff value.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)  # speed 50
	var manager := PowerUpManager.new()
	var effect := manager.apply("catnip", c)
	# Catnip applied +25 (50% of 50). Pretend something else added +10 during
	# the buff — total speed is now 50 + 25 + 10 = 85.
	c.speed += 10.0
	manager.tick(effect.duration)
	assert_almost_eq(c.speed, 60.0, 0.001, "external +10 survives catnip removal")
