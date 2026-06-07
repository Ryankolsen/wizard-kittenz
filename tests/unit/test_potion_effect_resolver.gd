extends GutTest

# PRD #358 / slice 3 — PotionEffectResolver dispatches HEAL_PERCENT /
# MANA_PERCENT / SHIELD onto a CharacterData. Mirrors test_spell_effect_resolver's
# _caster() factory pattern. SLEEPY_KITTEN is chosen because it carries a
# positive max_mp baseline (12 at level 1) so MANA_PERCENT has room to test.

func _caster() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)

func _health_potion() -> PotionDefinition:
	return PotionCatalog.find("health_potion")

func _mana_potion() -> PotionDefinition:
	return PotionCatalog.find("mana_potion")

func _shield_potion() -> PotionDefinition:
	return PotionCatalog.find("shield_potion")

func test_heal_percent_restores_percent_of_max_hp():
	var caster := _caster()
	caster.hp = 1
	var def := _health_potion()
	var expected := int(floor(float(caster.max_hp) * float(def.magnitude) / 100.0))
	var healed := PotionEffectResolver.apply(def, caster)
	assert_eq(healed, expected, "returns floor(max_hp * pct)")
	assert_eq(caster.hp, 1 + expected)

func test_heal_percent_clamps_at_max_hp_and_returns_actual():
	var caster := _caster()
	caster.hp = caster.max_hp - 1
	var def := _health_potion()
	var healed := PotionEffectResolver.apply(def, caster)
	assert_eq(healed, 1, "only the missing 1 HP is restored")
	assert_eq(caster.hp, caster.max_hp)

func test_heal_percent_at_full_returns_zero():
	var caster := _caster()
	caster.hp = caster.max_hp
	var healed := PotionEffectResolver.apply(_health_potion(), caster)
	assert_eq(healed, 0)
	assert_eq(caster.hp, caster.max_hp)

func test_mana_percent_restores_percent_of_max_mp():
	var caster := _caster()
	caster.magic_points = 0
	var def := _mana_potion()
	var expected := int(floor(float(caster.max_mp) * float(def.magnitude) / 100.0))
	var restored := PotionEffectResolver.apply(def, caster)
	assert_eq(restored, expected, "returns floor(max_mp * pct)")
	assert_eq(caster.magic_points, expected)

func test_mana_percent_clamps_at_max_mp_and_returns_actual():
	var caster := _caster()
	caster.magic_points = caster.max_mp - 1
	var restored := PotionEffectResolver.apply(_mana_potion(), caster)
	assert_eq(restored, 1, "only the missing 1 MP is restored")
	assert_eq(caster.magic_points, caster.max_mp)

func test_mana_percent_at_full_returns_zero():
	var caster := _caster()
	caster.magic_points = caster.max_mp
	var restored := PotionEffectResolver.apply(_mana_potion(), caster)
	assert_eq(restored, 0)
	assert_eq(caster.magic_points, caster.max_mp)

func test_shield_adds_shield_pool_and_duration():
	var caster := _caster()
	var def := _shield_potion()
	var applied := PotionEffectResolver.apply(def, caster)
	assert_eq(applied, def.magnitude, "returns the shield amount granted")
	assert_eq(caster.shield_amount(), def.magnitude)
	assert_almost_eq(caster.shield_remaining(), def.duration, 0.001)

func test_null_definition_returns_zero():
	var caster := _caster()
	assert_eq(PotionEffectResolver.apply(null, caster), 0)

func test_null_target_returns_zero():
	assert_eq(PotionEffectResolver.apply(_health_potion(), null), 0)
