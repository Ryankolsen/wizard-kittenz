extends GutTest

# Issue #144: active buff system on CharacterData powering PARTY_BUFF
# (Cozy Aura: +3 defense and +3 magic_resistance for 15s) and GROUP_REGEN
# (Regen Snooze: 2 HP/sec for 15s).

func _target() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)

func _party_buff() -> Spell:
	return Spell.make("cozy_aura", "Cozy Aura", Spell.EffectKind.PARTY_BUFF, 0, 4.0)

func _group_regen() -> Spell:
	return Spell.make("regen_snooze", "Regen Snooze", Spell.EffectKind.GROUP_REGEN, 0, 3.5)


func test_party_buff_raises_defense_immediately():
	var target := _target()
	var base_defense := target.defense
	SpellEffectResolver.apply(_party_buff(), target, [target])
	assert_eq(target.defense, base_defense + 3, "PARTY_BUFF adds +3 defense on apply")


func test_party_buff_reverts_defense_on_expiry():
	var target := _target()
	var base_defense := target.defense
	SpellEffectResolver.apply(_party_buff(), target, [target])
	target.tick_buffs(15.0)
	assert_eq(target.defense, base_defense, "defense returns to baseline after 15s")


func test_party_buff_reverts_magic_resistance_on_expiry():
	var target := _target()
	var base_mr := target.magic_resistance
	SpellEffectResolver.apply(_party_buff(), target, [target])
	assert_eq(target.magic_resistance, base_mr + 3, "PARTY_BUFF adds +3 magic_resistance on apply")
	target.tick_buffs(15.0)
	assert_eq(target.magic_resistance, base_mr, "magic_resistance returns to baseline after 15s")


func test_group_regen_ticks_hp_each_second():
	var target := _target()
	target.hp = target.max_hp / 2
	var before := target.hp
	SpellEffectResolver.apply(_group_regen(), target, [target])
	target.tick_buffs(1.0)
	assert_eq(target.hp, before + 2, "GROUP_REGEN heals 2 HP after a 1-second tick")


func test_group_regen_stops_after_15_seconds():
	var target := _target()
	target.hp = 1
	SpellEffectResolver.apply(_group_regen(), target, [target])
	target.tick_buffs(15.0)
	var hp_after_duration := target.hp
	target.tick_buffs(1.0)
	assert_eq(target.hp, hp_after_duration, "no further heal after the 15s window")


func test_group_regen_does_not_stack_with_passive_regen():
	# Passive regen lives in Player._tick_regeneration; tick_buffs only drives
	# the GROUP_REGEN HoT. With both notionally "active", a single tick_buffs
	# call must deliver exactly 2 HP (the buff's per-second amount), not 3.
	var target := _target()
	assert_eq(target.regeneration, 2, "Sleepy Kitten baseline passive regen is 2 (PRD #316)")
	target.hp = 1
	var before := target.hp
	SpellEffectResolver.apply(_group_regen(), target, [target])
	target.tick_buffs(1.0)
	assert_eq(target.hp, before + 2, "GROUP_REGEN tick contributes exactly 2 HP, no passive add-on")


func test_reapplying_party_buff_refreshes_duration_not_stat():
	var target := _target()
	var base_defense := target.defense
	SpellEffectResolver.apply(_party_buff(), target, [target])
	target.tick_buffs(10.0)
	assert_eq(target.defense, base_defense + 3, "still buffed after 10s")
	SpellEffectResolver.apply(_party_buff(), target, [target])
	assert_eq(target.defense, base_defense + 3, "re-applying does not stack (+3, not +6)")
	# Duration refreshed: 10s after the second apply should still be within
	# the 15s window, so the buff is still active.
	target.tick_buffs(10.0)
	assert_eq(target.defense, base_defense + 3, "duration was refreshed; still buffed at t=20s relative to first cast")
	target.tick_buffs(5.0)
	assert_eq(target.defense, base_defense, "buff reverts 15s after the refresh")
