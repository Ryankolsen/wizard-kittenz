extends GutTest

# Issue #459: ItemPassiveEffectResolver dispatches an equipped item's passive
# effect by item id, mirroring SpellEffectResolver's "dispatch by id" shape
# (Catnip Curse, Iron Hide, etc.) but for item passives instead of spells.
# Scene-tree-free — CharacterData stands in for the caster, same convention
# as test_spell_effect_resolver.gd.

func _caster() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)

func test_resolve_dispatches_guardians_locket_to_lifesteal():
	var caster := _caster()
	caster.hp = 1
	caster.max_hp = 100
	ItemPassiveEffectResolver.resolve("guardians_locket", caster, 100)
	assert_true(caster.hp > 1, "guardians_locket dispatches to the Lifesteal handler and heals the caster")

func test_resolve_unrecognized_item_id_is_no_op():
	var caster := _caster()
	caster.hp = 1
	caster.max_hp = 100
	ItemPassiveEffectResolver.resolve("not_a_real_item", caster, 100)
	assert_eq(caster.hp, 1, "unrecognized item id is a no-op, not an error")

# --- Crit Echo (issue #462) ---

func _rng_seeded_to_roll_below(threshold: float) -> RandomNumberGenerator:
	# CRIT_ECHO_CHANCE is 0.3; seed 13's first randf() (~0.062) is well below
	# that, giving a deterministic "cooldown preserved" roll for tests.
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	assert_lt(rng.randf(), threshold, "test setup: seed 13's first roll must land under CRIT_ECHO_CHANCE")
	rng.seed = 13
	return rng

func test_crit_echo_triggers_on_crit_when_equipped():
	var spell := Spell.make("test_spell", "Test Spell", Spell.EffectKind.DAMAGE, 10, 5.0)
	spell.cooldown_remaining = 5.0
	var rng := _rng_seeded_to_roll_below(ItemPassiveEffectResolver.CRIT_ECHO_CHANCE)
	var preserved := ItemPassiveEffectResolver.resolve_on_crit("executioners_signet", spell, true, rng)
	assert_true(preserved, "a successful Crit Echo roll must report the cooldown was preserved")
	assert_eq(spell.cooldown_remaining, 0.0, "a successful Crit Echo roll must refund the cooldown")

func test_crit_echo_no_op_on_non_crit():
	var spell := Spell.make("test_spell", "Test Spell", Spell.EffectKind.DAMAGE, 10, 5.0)
	spell.cooldown_remaining = 5.0
	var rng := _rng_seeded_to_roll_below(ItemPassiveEffectResolver.CRIT_ECHO_CHANCE)
	var preserved := ItemPassiveEffectResolver.resolve_on_crit("executioners_signet", spell, false, rng)
	assert_false(preserved, "a non-crit must never trigger Crit Echo, even on a roll that would otherwise succeed")
	assert_eq(spell.cooldown_remaining, 5.0, "a non-crit must leave the cooldown consumed normally")

func test_crit_echo_unequipped_never_preserves_cooldown():
	var spell := Spell.make("test_spell", "Test Spell", Spell.EffectKind.DAMAGE, 10, 5.0)
	spell.cooldown_remaining = 5.0
	var rng := _rng_seeded_to_roll_below(ItemPassiveEffectResolver.CRIT_ECHO_CHANCE)
	var preserved := ItemPassiveEffectResolver.resolve_on_crit("not_equipped", spell, true, rng)
	assert_false(preserved, "an item id with no Crit Echo passive must never preserve the cooldown")
	assert_eq(spell.cooldown_remaining, 5.0, "without Crit Echo the cooldown always consumes normally")

# --- Thorns (issue #463) ---

func test_thorns_reflects_damage_when_equipped():
	var attacker := _caster()
	attacker.hp = 100
	attacker.max_hp = 100
	var reflected := ItemPassiveEffectResolver.resolve_on_hit_taken("bramble_plate", attacker, 100)
	var expected := int(ceil(100 * ItemPassiveEffectResolver.THORNS_PCT))
	assert_eq(reflected, expected, "Thorns must reflect THORNS_PCT of the incoming damage")
	assert_eq(attacker.hp, 100 - expected, "the reflected damage must actually be dealt to the attacker")

func test_thorns_no_reflection_when_unequipped():
	var attacker := _caster()
	attacker.hp = 100
	attacker.max_hp = 100
	var reflected := ItemPassiveEffectResolver.resolve_on_hit_taken("not_a_real_item", attacker, 100)
	assert_eq(reflected, 0, "no Thorns passive means no reflected damage")
	assert_eq(attacker.hp, 100, "an unequipped wearer must never reflect damage back")

func test_thorns_no_reflection_on_zero_damage():
	var attacker := _caster()
	attacker.hp = 100
	attacker.max_hp = 100
	var reflected := ItemPassiveEffectResolver.resolve_on_hit_taken("bramble_plate", attacker, 0)
	assert_eq(reflected, 0, "zero incoming damage must never produce a reflection")
	assert_eq(attacker.hp, 100, "zero incoming damage must leave the attacker untouched")
