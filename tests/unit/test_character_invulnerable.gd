extends GutTest

# Issue #457: invulnerable timed flag on CharacterData, ticked down the same
# way as the existing absorb-shield (add_shield/tick_shield/take_damage),
# proven by Phase Tome I. While active, take_damage fully negates incoming
# damage instead of soaking a finite pool like the shield does.

func _caster() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)

# Slice 1 — Thinnest end-to-end: invulnerability negates damage.
func test_invulnerable_negates_damage():
	var c := _caster()
	c.set_invulnerable(2.0)
	c.take_damage(999)
	assert_eq(c.hp, c.max_hp, "invulnerable caster takes no damage")

# Slice 2 — Content details: expiry restores normal damage.
func test_invulnerable_expires_after_duration():
	var c := _caster()
	c.set_invulnerable(2.0)
	c.tick_invulnerable(2.0)
	assert_false(c.is_invulnerable(), "flag clears once duration elapses")
	c.take_damage(5)
	assert_eq(c.hp, c.max_hp - 5, "post-expiry damage hits hp normally")

# Slice 3 — Edge cases: partial tick, refresh, no-flag regression, invalid input.
func test_invulnerable_partial_tick_still_active():
	var c := _caster()
	c.set_invulnerable(2.0)
	c.tick_invulnerable(1.0)
	assert_true(c.is_invulnerable(), "flag still active before full duration elapses")

func test_re_setting_invulnerable_takes_longer_duration():
	var c := _caster()
	c.set_invulnerable(2.0)
	c.set_invulnerable(5.0)
	c.tick_invulnerable(2.0)
	assert_true(c.is_invulnerable(), "refresh takes the longer duration, not the newest call")

func test_take_damage_without_invulnerable_unchanged_regression():
	var c := _caster()
	c.take_damage(3)
	assert_eq(c.hp, c.max_hp - 3, "no-invulnerable path still hits hp")

func test_set_invulnerable_rejects_nonpositive_duration():
	var c := _caster()
	c.set_invulnerable(0.0)
	assert_false(c.is_invulnerable(), "zero duration is a no-op")
