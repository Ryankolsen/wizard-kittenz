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

func test_taunt_emits_on_broadcaster_per_enemy():
	# Co-op TAUNT fan-out: each stamped enemy produces one broadcaster
	# emission with (caster_id, enemy_id, duration). The broadcaster's
	# own guards drop empties; this test pins that the resolver routes
	# the tuple through.
	var caster := _caster(0)
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	e1.enemy_id = "r3_e0"
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.BAT)
	e2.enemy_id = "r3_e1"
	var bc := TauntBroadcaster.new()
	var captured: Array = []
	bc.taunt_applied.connect(func(c: String, e: String, d: float):
		captured.append([c, e, d])
	)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 2.0)
	SpellEffectResolver.apply(spell, caster, [e1, e2], null, bc, "u1")
	assert_eq(captured.size(), 2)
	assert_eq(captured[0], ["u1", "r3_e0", 2.0])
	assert_eq(captured[1], ["u1", "r3_e1", 2.0])

func test_taunt_stamps_source_id_when_caster_id_provided():
	# Cross-client identity prerequisite for the future RemoteTauntApplier:
	# the resolver records the casting player's Nakama id on the enemy so a
	# receiving client (which has no caster CharacterData object) can match
	# the taunt back to the right player.
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	enemy.enemy_id = "r1_e0"
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [enemy], null, null, "u42")
	assert_eq(enemy.taunt_source_id, "u42",
		"taunt_source_id stamped from caster_id for cross-client identity")

func test_taunt_leaves_source_id_unset_in_solo_path():
	# Solo / pre-handshake path passes empty caster_id; resolver must not
	# pollute the field with "" when there is no cross-client identity.
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	enemy.taunt_source_id = "previous_caster"
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy.taunt_source_id, "previous_caster",
		"empty caster_id leaves taunt_source_id untouched")

func test_taunt_source_id_clears_on_expiry():
	# tick_taunt's expiry path must clear taunt_source_id alongside
	# taunt_target — otherwise the cross-client identity outlives the
	# taunt window and a stale id leaks into the next taunt cycle.
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [enemy], null, null, "u42")
	assert_eq(enemy.taunt_source_id, "u42")
	enemy.tick_taunt(1.0)
	assert_eq(enemy.taunt_target, null)
	assert_eq(enemy.taunt_source_id, "",
		"taunt_source_id cleared on expiry alongside taunt_target")

func test_taunt_ignores_non_taunt_targets_without_crash():
	# CharacterData has no taunt_target field — TAUNT should skip it duck-type
	# style without erroring.
	var caster := _caster(0)
	var other := _caster(0)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [other])
	assert_true(true, "no crash applying TAUNT to a non-taunt-capable target")
