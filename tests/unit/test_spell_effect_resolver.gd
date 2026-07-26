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
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	enemy.taunt_target = other
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 2.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy.taunt_target, caster, "taunt redirects target to caster")
	assert_almost_eq(enemy.taunt_remaining, 2.0, 0.001)

func test_taunt_taunts_multiple_enemies():
	var caster := _caster(0)
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.ROGUE_ROOMBA)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.5)
	SpellEffectResolver.apply(spell, caster, [e1, e2])
	assert_eq(e1.taunt_target, caster)
	assert_eq(e2.taunt_target, caster)

func test_taunt_expires_after_duration():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_true(enemy.is_taunted(), "taunt active immediately after cast")
	enemy.tick_taunt(1.0)
	assert_false(enemy.is_taunted(), "taunt cleared after duration elapses")
	assert_eq(enemy.taunt_target, null)

func test_taunt_remaining_decays_partially():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
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
	var bystander := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
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
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	e1.enemy_id = "r3_e0"
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.ROGUE_ROOMBA)
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
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	enemy.enemy_id = "r1_e0"
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [enemy], null, null, "u42")
	assert_eq(enemy.taunt_source_id, "u42",
		"taunt_source_id stamped from caster_id for cross-client identity")

func test_taunt_leaves_source_id_unset_in_solo_path():
	# Solo / pre-handshake path passes empty caster_id; resolver must not
	# pollute the field with "" when there is no cross-client identity.
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
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
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [enemy], null, null, "u42")
	assert_eq(enemy.taunt_source_id, "u42")
	enemy.tick_taunt(1.0)
	assert_eq(enemy.taunt_target, null)
	assert_eq(enemy.taunt_source_id, "",
		"taunt_source_id cleared on expiry alongside taunt_target")

func test_smart_heal_picks_lowest_hp_pct_target():
	# Issue #141: SMART_HEAL routes to the ally with the lowest HP percentage,
	# not the caster. Caster at full HP, ally A at 80%, ally B at 40% — B wins.
	var caster := _caster(0)
	var ally_a := _caster(0)
	ally_a.max_hp = 10
	ally_a.hp = 8
	var ally_b := _caster(0)
	ally_b.max_hp = 10
	ally_b.hp = 4
	var ally_b_start := ally_b.hp
	var ally_a_start := ally_a.hp
	var caster_start := caster.hp
	var spell := Spell.make("sh", "Fuzzy Warmth", Spell.EffectKind.SMART_HEAL, 3, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [ally_a, ally_b])
	assert_eq(healed, 3, "spell.power 3 heals the 40% ally for 3")
	assert_eq(ally_b.hp, ally_b_start + 3, "lowest-HP-pct ally is healed")
	assert_eq(ally_a.hp, ally_a_start, "higher-HP-pct ally untouched")
	assert_eq(caster.hp, caster_start, "caster untouched when an ally needs healing more")

func test_smart_heal_falls_back_to_caster_when_targets_empty():
	var caster := _caster(0)
	caster.hp = caster.max_hp - 5
	var spell := Spell.make("sh", "Fuzzy Warmth", Spell.EffectKind.SMART_HEAL, 3, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [])
	assert_eq(healed, 3, "empty targets falls back to caster heal")
	assert_eq(caster.hp, caster.max_hp - 2)

func test_smart_heal_falls_back_to_caster_when_all_targets_full_hp():
	var caster := _caster(0)
	caster.hp = caster.max_hp - 5
	var ally := _caster(0)
	# ally is at full HP, so ineligible — caster (missing HP) is healed instead.
	var spell := Spell.make("sh", "Fuzzy Warmth", Spell.EffectKind.SMART_HEAL, 3, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [ally])
	assert_eq(healed, 3, "no wounded target falls back to caster")
	assert_eq(caster.hp, caster.max_hp - 2)
	assert_eq(ally.hp, ally.max_hp, "full-HP ally unchanged")

func test_aoe_heal_heals_every_target():
	var caster := _caster(0)
	var a := _caster(0)
	a.hp = a.max_hp - 5
	var b := _caster(0)
	b.hp = b.max_hp - 5
	var spell := Spell.make("ah", "Warm Blanket", Spell.EffectKind.AOE_HEAL, 3, 2.5)
	SpellEffectResolver.apply(spell, caster, [a, b])
	assert_eq(a.hp, a.max_hp - 2, "ally a healed for 3")
	assert_eq(b.hp, b.max_hp - 2, "ally b healed for 3")

func test_aoe_heal_return_value_is_sum_across_targets():
	# Two allies each missing 3 HP, spell power 5: each clamps at 3 HP restored,
	# so total = 6.
	var caster := _caster(0)
	var a := _caster(0)
	a.hp = a.max_hp - 3
	var b := _caster(0)
	b.hp = b.max_hp - 3
	var spell := Spell.make("ah", "Nap of the Gods", Spell.EffectKind.AOE_HEAL, 5, 6.0)
	var healed := SpellEffectResolver.apply(spell, caster, [a, b])
	assert_eq(healed, 6, "return value is sum of clamped HP restored")

func test_group_regen_does_not_crash_and_returns_zero():
	# Stub branch (#141): real buff application lands in slice #3. Solo path
	# must no-op safely and report zero instant HP restored.
	var caster := _caster(0)
	var a := _caster(0)
	a.hp = a.max_hp - 5
	var spell := Spell.make("gr", "Regen Snooze", Spell.EffectKind.GROUP_REGEN, 2, 3.5)
	var healed := SpellEffectResolver.apply(spell, caster, [a])
	assert_eq(healed, 0, "stub branch returns zero — no instant HP")
	assert_eq(a.hp, a.max_hp - 5, "target HP unchanged by stub")

func test_party_buff_does_not_crash_and_returns_zero():
	var caster := _caster(0)
	var a := _caster(0)
	var spell := Spell.make("pb", "Cozy Aura", Spell.EffectKind.PARTY_BUFF, 3, 4.0)
	var healed := SpellEffectResolver.apply(spell, caster, [a])
	assert_eq(healed, 0, "stub branch returns zero — no instant HP")

# ---- BUFF resolver fix (issue #423) --------------------------------------

func test_catnip_curse_boosts_damage_output_then_reverts():
	var caster := _caster(0)
	assert_almost_eq(caster.get_damage_multiplier(), 1.0, 0.0001, "no buff at baseline")
	var spell := Spell.make("catnip_curse", "Catnip Curse", Spell.EffectKind.BUFF, 4, 3.0, 0, 4)
	SpellEffectResolver.apply(spell, caster, [])
	assert_almost_eq(caster.get_damage_multiplier(), SpellEffectResolver.CATNIP_CURSE_MULT, 0.0001,
		"Catnip Curse boosts the caster's damage multiplier")
	caster.tick_buffs(SpellEffectResolver.CATNIP_CURSE_DURATION)
	assert_almost_eq(caster.get_damage_multiplier(), 1.0, 0.0001,
		"damage multiplier reverts once the buff expires")

func test_maximum_chonk_boosts_stats_then_reverts():
	var caster := _caster(0)
	var base_attack := caster.attack
	var base_defense := caster.defense
	var base_mr := caster.magic_resistance
	var spell := Spell.make("maximum_chonk", "Maximum Chonk", Spell.EffectKind.BUFF, 8, 6.0)
	SpellEffectResolver.apply(spell, caster, [])
	assert_eq(caster.attack, base_attack + SpellEffectResolver.MAXIMUM_CHONK_STAT_AMOUNT)
	assert_eq(caster.defense, base_defense + SpellEffectResolver.MAXIMUM_CHONK_STAT_AMOUNT)
	assert_eq(caster.magic_resistance, base_mr + SpellEffectResolver.MAXIMUM_CHONK_STAT_AMOUNT)
	caster.tick_buffs(SpellEffectResolver.MAXIMUM_CHONK_DURATION)
	assert_eq(caster.attack, base_attack, "attack reverts after expiry")
	assert_eq(caster.defense, base_defense, "defense reverts after expiry")
	assert_eq(caster.magic_resistance, base_mr, "magic_resistance reverts after expiry")

func test_iron_hide_applies_defense_buff_and_shield_in_one_cast():
	var caster := _caster(0)
	var base_defense := caster.defense
	var spell := Spell.make("iron_hide", "Iron Hide", Spell.EffectKind.BUFF, 0, 10.0)
	SpellEffectResolver.apply(spell, caster, [])
	assert_eq(caster.defense, base_defense + SpellEffectResolver.IRON_HIDE_DEFENSE_AMOUNT,
		"Iron Hide boosts defense")
	assert_eq(caster.shield_amount(), SpellEffectResolver.IRON_HIDE_SHIELD_AMOUNT,
		"Iron Hide also grants a shield")
	assert_almost_eq(caster.shield_remaining(), SpellEffectResolver.IRON_HIDE_DURATION, 0.0001)

# ---- PARTY_SHIELD / Nine Lives (issue #424) ------------------------------

func test_party_shield_applies_shield_to_all_targets():
	var caster := _caster(0)
	var a := _caster(0)
	var b := _caster(0)
	var spell := Spell.make("cozy_cocoon", "Cozy Cocoon", Spell.EffectKind.PARTY_SHIELD, 10, 5.0, 0, 10)
	var total := SpellEffectResolver.apply(spell, caster, [a, b])
	assert_eq(total, 0, "PARTY_SHIELD deals no instant HP")
	assert_eq(a.shield_amount(), SpellEffectResolver.COZY_COCOON_SHIELD_AMOUNT)
	assert_almost_eq(a.shield_remaining(), SpellEffectResolver.COZY_COCOON_DURATION, 0.0001)
	assert_eq(b.shield_amount(), SpellEffectResolver.COZY_COCOON_SHIELD_AMOUNT)
	assert_almost_eq(b.shield_remaining(), SpellEffectResolver.COZY_COCOON_DURATION, 0.0001)

func test_party_shield_ignores_caster_when_not_in_targets():
	var caster := _caster(0)
	var spell := Spell.make("cozy_cocoon", "Cozy Cocoon", Spell.EffectKind.PARTY_SHIELD, 10, 5.0, 0, 10)
	SpellEffectResolver.apply(spell, caster, [])
	assert_eq(caster.shield_amount(), 0, "caster is untouched when not in the targets array")

func test_nine_lives_fully_heals_and_shields_lowest_hp_ally():
	var caster := _caster(0)
	var low := _caster(0)
	low.hp = 1
	var high := _caster(0)
	high.hp = high.max_hp - 1
	var spell := Spell.make("nine_lives", "Nine Lives", Spell.EffectKind.SMART_HEAL, 0, 10.0, 0, 20)
	var healed := SpellEffectResolver.apply(spell, caster, [low, high])
	assert_eq(low.hp, low.max_hp, "Nine Lives fully heals the lowest-HP ally")
	assert_eq(healed, low.max_hp - 1, "return value is the HP actually restored")
	assert_eq(low.shield_amount(), SpellEffectResolver.NINE_LIVES_SHIELD_AMOUNT)
	assert_almost_eq(low.shield_remaining(), SpellEffectResolver.NINE_LIVES_DURATION, 0.0001)
	assert_eq(high.hp, high.max_hp - 1, "the higher-HP ally is untouched")
	assert_eq(high.shield_amount(), 0)

func test_unknown_buff_id_is_a_safe_no_op():
	var caster := _caster(0)
	var base_defense := caster.defense
	var spell := Spell.make("mystery_buff", "Mystery Buff", Spell.EffectKind.BUFF, 5, 2.0)
	SpellEffectResolver.apply(spell, caster, [])
	assert_eq(caster.defense, base_defense, "unrecognized BUFF id does not mutate the caster")
	assert_almost_eq(caster.get_damage_multiplier(), 1.0, 0.0001)

func test_taunt_ignores_non_taunt_targets_without_crash():
	# CharacterData has no taunt_target field — TAUNT should skip it duck-type
	# style without erroring.
	var caster := _caster(0)
	var other := _caster(0)
	var spell := Spell.make("t", "Taunt", Spell.EffectKind.TAUNT, 0, 1.0)
	SpellEffectResolver.apply(spell, caster, [other])
	assert_true(true, "no crash applying TAUNT to a non-taunt-capable target")

# ---- DOT / Bloodclaw Rend / Arcane Wildfire (issue #426) -----------------
# Asserts via EnemyData's #421 tracker public state (_dots), not by manually
# ticking time forward — tick behavior itself is covered by test_enemy_data.gd.

func test_bloodclaw_rend_applies_dot_to_single_target():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("bloodclaw_rend", "Bloodclaw Rend", Spell.EffectKind.DOT, 4, 3.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy._dots.size(), 1, "Bloodclaw Rend applies exactly one DOT stack")
	assert_eq(enemy._dots[0].amount, 4, "tick amount matches spell.power (+ magic_attack)")
	assert_almost_eq(enemy._dots[0].remaining, SpellEffectResolver.BLOODCLAW_REND_DOT_DURATION, 0.0001)

func test_bloodclaw_rend_only_hits_first_living_target():
	var caster := _caster(0)
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.ROGUE_ROOMBA)
	var spell := Spell.make("bloodclaw_rend", "Bloodclaw Rend", Spell.EffectKind.DOT, 4, 3.0)
	SpellEffectResolver.apply(spell, caster, [e1, e2])
	assert_eq(e1._dots.size(), 1, "single-target DOT hits the first target")
	assert_eq(e2._dots.size(), 0, "single-target DOT does not spread to a second target")

func test_arcane_wildfire_applies_dot_to_every_target_in_range():
	var caster := _caster(0)
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.ROGUE_ROOMBA)
	var spell := Spell.make("arcane_wildfire", "Arcane Wildfire", Spell.EffectKind.DOT, 3, 4.0, 0, 10)
	SpellEffectResolver.apply(spell, caster, [e1, e2])
	assert_eq(e1._dots.size(), 1, "Arcane Wildfire (AREA+DOT) hits the first target")
	assert_eq(e1._dots[0].amount, 3)
	assert_almost_eq(e1._dots[0].remaining, SpellEffectResolver.ARCANE_WILDFIRE_DOT_DURATION, 0.0001)
	assert_eq(e2._dots.size(), 1, "Arcane Wildfire also hits a second target in range")
	assert_eq(e2._dots[0].amount, 3)

func test_dot_tick_amount_scales_with_magic_attack():
	var caster := _caster(5)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("bloodclaw_rend", "Bloodclaw Rend", Spell.EffectKind.DOT, 4, 3.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy._dots[0].amount, 9, "spell.power 4 + magic_attack 5 = 9")

func test_recasting_dot_on_same_target_stacks_rather_than_refreshes():
	# Matches #421's apply_dot, which always appends a new tracked stack —
	# confirmed consistent here rather than inventing new refresh semantics.
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("bloodclaw_rend", "Bloodclaw Rend", Spell.EffectKind.DOT, 4, 3.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy._dots.size(), 2, "re-casting DOT on an already-DOT'd target stacks a second entry")

func test_dot_skips_dead_targets():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	enemy.take_damage(999)
	var spell := Spell.make("bloodclaw_rend", "Bloodclaw Rend", Spell.EffectKind.DOT, 4, 3.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy._dots.size(), 0, "a dead target does not receive a DOT")

func test_unknown_dot_id_is_a_safe_no_op():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("mystery_dot", "Mystery DOT", Spell.EffectKind.DOT, 4, 3.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy._dots.size(), 0, "unrecognized DOT id does not mutate the target")

# ---- DEBUFF / Mind Sunder (issue #427) ------------------------------------
# Asserts via EnemyData's #421 tracker (defense field + _debuffs), not by
# manually ticking time forward — expiry-timing itself is covered by
# test_enemy_data.gd.

func test_mind_sunder_reduces_target_defense_immediately():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var base_defense := enemy.defense
	var spell := Spell.make("mind_sunder", "Mind Sunder", Spell.EffectKind.DEBUFF, 4, 5.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy.defense, base_defense - 4, "Mind Sunder lowers defense by 4 immediately")
	assert_eq(enemy._debuffs.size(), 1, "Mind Sunder tracks exactly one debuff stack")

func test_mind_sunder_increases_incoming_damage_via_damage_resolver():
	var attacker := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	attacker.attack = 10
	var debuffed := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	var baseline := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	var caster := _caster(0)
	var spell := Spell.make("mind_sunder", "Mind Sunder", Spell.EffectKind.DEBUFF, 4, 5.0)
	SpellEffectResolver.apply(spell, caster, [debuffed])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var dealt_to_debuffed := DamageResolver.apply(attacker, debuffed, rng)
	rng.seed = 1
	var dealt_to_baseline := DamageResolver.apply(attacker, baseline, rng)
	assert_gt(dealt_to_debuffed, dealt_to_baseline, "lowered defense from Mind Sunder increases incoming damage")

func test_mind_sunder_only_hits_first_living_target():
	var caster := _caster(0)
	var e1 := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var e2 := EnemyData.make_new(EnemyData.EnemyKind.ROGUE_ROOMBA)
	var spell := Spell.make("mind_sunder", "Mind Sunder", Spell.EffectKind.DEBUFF, 4, 5.0)
	SpellEffectResolver.apply(spell, caster, [e1, e2])
	assert_eq(e1._debuffs.size(), 1, "single-target debuff hits the first target")
	assert_eq(e2._debuffs.size(), 0, "single-target debuff does not spread to a second target")

func test_mind_sunder_skips_dead_targets():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	enemy.take_damage(999)
	var spell := Spell.make("mind_sunder", "Mind Sunder", Spell.EffectKind.DEBUFF, 4, 5.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy._debuffs.size(), 0, "a dead target does not receive a debuff")

func test_unknown_debuff_id_is_a_safe_no_op():
	var caster := _caster(0)
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	var spell := Spell.make("mystery_debuff", "Mystery Debuff", Spell.EffectKind.DEBUFF, 4, 5.0)
	SpellEffectResolver.apply(spell, caster, [enemy])
	assert_eq(enemy._debuffs.size(), 0, "unrecognized DEBUFF id does not mutate the target")
