extends GutTest

# Issue #128: HEAL and TAUNT dispatch in SpellEffectResolver. HEAL restores
# HP to the caster scaled by spell.power + magic_attack (clamped at max_hp);
# TAUNT sets each target enemy's taunt_target to the caster for the spell's
# cooldown duration. Existing DAMAGE/AREA branches are covered by
# test_spell_combat_stats.gd — these tests focus on the two new branches.

func _caster(magic_attack: int = 0) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.magic_attack = magic_attack
	return c

func test_heal_restores_hp_to_caster():
	var caster := _caster(0)
	caster.hp = caster.max_hp - 5
	var spell := Spell.make("h", "Heal", Spell.EffectKind.HEAL, 3, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [])
	assert_eq(healed, 3, "spell.power 3 + magic_attack 0 heals 3")
	assert_eq(caster.hp, caster.max_hp - 2)

func test_heal_clamps_at_max_hp():
	var caster := _caster(0)
	caster.hp = caster.max_hp
	var spell := Spell.make("h", "Heal", Spell.EffectKind.HEAL, 5, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [])
	assert_eq(healed, 0, "full HP heals zero")
	assert_eq(caster.hp, caster.max_hp)

func test_heal_clamps_when_partial_overflow():
	var caster := _caster(0)
	caster.hp = caster.max_hp - 2
	var spell := Spell.make("h", "Heal", Spell.EffectKind.HEAL, 10, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [])
	assert_eq(healed, 2, "heals only the missing 2 HP")
	assert_eq(caster.hp, caster.max_hp)

func test_heal_scales_with_power():
	var caster1 := _caster(0)
	caster1.hp = 1
	var caster2 := _caster(0)
	caster2.hp = 1
	var small := Spell.make("h1", "Small Heal", Spell.EffectKind.HEAL, 2, 1.0)
	var big := Spell.make("h2", "Big Heal", Spell.EffectKind.HEAL, 5, 1.0)
	var small_healed := SpellEffectResolver.apply(small, caster1, [])
	var big_healed := SpellEffectResolver.apply(big, caster2, [])
	assert_true(big_healed > small_healed, "higher power heals more")

func test_heal_scales_with_magic_attack():
	var caster := _caster(4)
	caster.hp = 1
	var spell := Spell.make("h", "Heal", Spell.EffectKind.HEAL, 3, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [])
	assert_eq(healed, 7, "spell.power 3 + magic_attack 4 = 7")

func test_taunt_sets_enemy_target_to_caster():
	var caster := _caster(0)
	var other := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	enemy.taunt_target = other
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 2.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy.taunt_target, caster, "taunt redirects target to caster")
	assert_almost_eq(enemy.taunt_remaining, 2.0, 0.001)

func test_taunt_taunts_multiple_enemies():
	var caster := _caster(0)
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.BAT)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.5)
	SpellEffectResolver.apply(spell, caster, [e1, e2])
	assert_eq(e1.taunt_target, caster)
	assert_eq(e2.taunt_target, caster)

func test_taunt_expires_after_duration():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_true(enemy.is_taunted(), "taunt active immediately after cast")
	enemy.tick_taunt(1.0)
	assert_false(enemy.is_taunted(), "taunt cleared after duration elapses")
	assert_eq(enemy.taunt_target, null)

func test_taunt_remaining_decays_partially():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 2.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	enemy.tick_taunt(0.5)
	assert_true(enemy.is_taunted())
	assert_almost_eq(enemy.taunt_remaining, 1.5, 0.001)
	assert_eq(enemy.taunt_target, caster)

func test_cooldown_blocks_repeat_cast():
	var caster := _caster(0)
	caster.hp = 1
	var spell := Spell.make("h", "Heal", Spell.EffectKind.HEAL, 3, 1.0)
	# First cast goes through.
	if spell.cast():
		SpellEffectResolver.apply(spell, caster, [])
	var hp_after_first := caster.hp
	# Second cast inside cooldown is gated and must not heal again.
	if spell.cast():
		SpellEffectResolver.apply(spell, caster, [])
	assert_eq(caster.hp, hp_after_first, "second cast on cooldown does not heal")

func test_heal_targets_list_ignored():
	# HEAL is a self-heal regardless of what's in the targets list.
	var caster := _caster(0)
	caster.hp = caster.max_hp - 5
	var bystander := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var spell := Spell.make("h", "Heal", Spell.EffectKind.HEAL, 3, 1.0)
	SpellEffectResolver.apply(spell, caster, [bystander])
	assert_eq(caster.hp, caster.max_hp - 2)
	assert_eq(bystander.hp, bystander.max_hp, "targets are not affected by HEAL")

func test_taunt_ignores_non_taunt_targets_without_crash():
	# CharacterData has no taunt_target field — TAUNT should skip it duck-type
	# style without erroring.
	var caster := _caster(0)
	var other := _caster(0)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [other])
	assert_true(true, "no crash applying TAUNT to a non-taunt-capable target")
