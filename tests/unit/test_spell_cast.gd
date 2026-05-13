extends GutTest

# Regression for: Q key "did nothing" because SpellEffectResolver was never
# called with actual targets — no visual feedback made it invisible even when
# working. These tests verify the full cast path: ready spell + enemy in range
# = damage applied.

func test_ready_spell_damages_enemy():
	var spell := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var hp_before := enemy.hp
	assert_true(spell.is_ready(), "freshly created spell should be ready")
	var cast_ok := spell.cast()
	assert_true(cast_ok, "cast() should succeed when ready")
	SpellEffectResolver.apply(spell, null, [enemy])
	assert_lt(enemy.hp, hp_before, "enemy hp should drop after spell apply")

func test_cast_sets_cooldown_preventing_immediate_recast():
	var spell := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	spell.cast()
	assert_false(spell.is_ready(), "spell should be on cooldown after cast")
	assert_false(spell.cast(), "second immediate cast should return false")

func test_spell_ready_after_tick():
	var spell := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	spell.cast()
	spell.tick(0.8)
	assert_true(spell.is_ready(), "spell should be ready again after full cooldown ticks")

func test_no_damage_with_empty_target_list():
	# Reproduces the log output: cast succeeded, applying to 0 targets.
	# Cast should still succeed and set cooldown; just no damage dealt.
	var spell := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	var cast_ok := spell.cast()
	assert_true(cast_ok, "cast succeeds even with no enemies in range")
	var total := SpellEffectResolver.apply(spell, null, [])
	assert_eq(total, 0, "no damage when target list is empty")
	assert_false(spell.is_ready(), "cooldown still consumed even with no targets")
