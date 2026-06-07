extends GutTest

# PRD #358 slice 2 (issue #360). Absorb-shield mechanic on CharacterData —
# add_shield() / tick_shield() / take_damage() integration so a future
# SHIELD spell and the Shield potion both flow through one code path.

func _caster() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)

# Slice 1 — Thinnest end-to-end: shield absorbs damage before HP.
func test_shield_absorbs_damage_before_hp():
	var c := _caster()
	c.add_shield(10, 5.0)
	c.take_damage(6)
	assert_eq(c.hp, c.max_hp, "shield should soak the 6 damage; hp untouched")
	assert_eq(c.shield_amount(), 4, "shield should drop from 10 to 4")

# Slice 2 — Content details: spillover and refresh.
func test_damage_exceeding_shield_spills_to_hp():
	var c := _caster()
	c.add_shield(10, 5.0)
	c.take_damage(15)
	assert_eq(c.shield_amount(), 0, "shield zeroed after over-cap hit")
	assert_eq(c.hp, c.max_hp - 5, "5 damage spills to hp")

func test_re_adding_shield_takes_larger_pool():
	var c := _caster()
	c.add_shield(10, 5.0)
	c.add_shield(20, 5.0)
	assert_eq(c.shield_amount(), 20, "refresh takes the larger pool")

func test_re_adding_smaller_shield_keeps_larger_pool():
	var c := _caster()
	c.add_shield(20, 5.0)
	c.add_shield(10, 5.0)
	assert_eq(c.shield_amount(), 20, "smaller incoming pool does not shrink active shield")

# Slice 3 — Edge cases: expiry, no-shield regression, invalid inputs.
func test_shield_expires_after_duration():
	var c := _caster()
	c.add_shield(10, 5.0)
	c.tick_shield(5.0)
	assert_eq(c.shield_amount(), 0, "shield gone after duration elapses")
	c.take_damage(8)
	assert_eq(c.hp, c.max_hp - 8, "post-expiry damage hits hp normally")

func test_take_damage_without_shield_unchanged_regression():
	var c := _caster()
	c.take_damage(3)
	assert_eq(c.hp, c.max_hp - 3, "no-shield path still hits hp")

func test_add_shield_rejects_nonpositive_inputs():
	var c := _caster()
	c.add_shield(0, 5.0)
	assert_eq(c.shield_amount(), 0, "zero amount is a no-op")
	c.add_shield(10, 0.0)
	assert_eq(c.shield_amount(), 0, "zero duration is a no-op")
