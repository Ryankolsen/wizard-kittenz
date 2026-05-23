extends GutTest

# Issue #198: multiplicative damage-multiplier buff on CharacterData.
# Distinct from the stat-delta buff path (test_active_buff.gd) — this buff
# does not mutate a stored field, so DamageResolver must query the live
# multiplier at the moment of dealing damage.

func _target() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)

func test_damage_multiplier_default_is_one():
	var c := _target()
	assert_almost_eq(c.get_damage_multiplier(), 1.0, 0.0001)

func test_apply_mult_buff_changes_multiplier():
	var c := _target()
	c.add_damage_mult_buff(1.2, 60.0)
	assert_almost_eq(c.get_damage_multiplier(), 1.2, 0.0001)
	assert_true(c.has_active_buff(CharacterData.BUFF_GROUP_DAMAGE_MULT))

func test_mult_buff_expires_after_duration():
	var c := _target()
	c.add_damage_mult_buff(1.2, 60.0)
	c.tick_buffs(60.0)
	assert_almost_eq(c.get_damage_multiplier(), 1.0, 0.0001)
	assert_false(c.has_active_buff(CharacterData.BUFF_GROUP_DAMAGE_MULT))

func test_reapplying_same_mult_buff_refreshes_duration():
	var c := _target()
	c.add_damage_mult_buff(1.2, 60.0)
	c.tick_buffs(30.0)
	c.add_damage_mult_buff(1.2, 60.0)
	c.tick_buffs(45.0)
	# 30s in, refresh to 60s remaining, then 45s tick → 15s left. Still active,
	# still 1.2× (no stacking with itself).
	assert_almost_eq(c.get_damage_multiplier(), 1.2, 0.0001)

func test_mult_buff_does_not_stack_with_itself():
	# Reapply must not produce 1.2 * 1.2 = 1.44. One instance only.
	var c := _target()
	c.add_damage_mult_buff(1.2, 60.0)
	c.add_damage_mult_buff(1.2, 60.0)
	assert_almost_eq(c.get_damage_multiplier(), 1.2, 0.0001)

func test_zero_or_negative_magnitude_is_ignored():
	var c := _target()
	c.add_damage_mult_buff(0.0, 60.0)
	c.add_damage_mult_buff(-1.0, 60.0)
	assert_almost_eq(c.get_damage_multiplier(), 1.0, 0.0001)
	assert_false(c.has_active_buff(CharacterData.BUFF_GROUP_DAMAGE_MULT))

func test_zero_or_negative_duration_is_ignored():
	var c := _target()
	c.add_damage_mult_buff(1.2, 0.0)
	c.add_damage_mult_buff(1.2, -5.0)
	assert_almost_eq(c.get_damage_multiplier(), 1.0, 0.0001)
