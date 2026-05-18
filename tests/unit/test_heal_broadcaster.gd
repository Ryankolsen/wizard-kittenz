extends GutTest

# Issue #145: HealBroadcaster — the outbound seam SpellEffectResolver
# emits on after applying SMART_HEAL / AOE_HEAL / GROUP_REGEN /
# PARTY_BUFF locally. Mirrors the shape of TauntBroadcaster's tests:
# pin the contract for the guarded no-op (empty caster_id) and the
# emission tuple, plus the resolver-side fan-out per target.

func _capture(bc: HealBroadcaster) -> Array:
	var captured: Array = []
	bc.heal_applied.connect(func(c: String, t: String, kind: String, amount: int, duration: float):
		captured.append([c, t, kind, amount, duration])
	)
	return captured

func _ally(player_id: String = "") -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN)
	c.player_id = player_id
	return c


func test_on_heal_applied_emits_signal_with_tuple():
	var bc := HealBroadcaster.new()
	var captured := _capture(bc)
	assert_true(bc.on_heal_applied("u1", "u2", "AOE_HEAL", 5, 0.0))
	assert_eq(captured.size(), 1)
	assert_eq(captured[0][0], "u1")
	assert_eq(captured[0][1], "u2")
	assert_eq(captured[0][2], "AOE_HEAL")
	assert_eq(captured[0][3], 5)
	assert_eq(captured[0][4], 0.0)


func test_on_heal_applied_rejects_empty_caster_id():
	# An empty caster_id means the receiving client can't resolve the
	# casting Player on its side — no point sending it on the wire.
	var bc := HealBroadcaster.new()
	var captured := _capture(bc)
	assert_false(bc.on_heal_applied("", "u2", "AOE_HEAL", 5, 0.0))
	assert_eq(captured.size(), 0, "no emission on empty caster_id")


func test_resolver_emits_for_smart_heal():
	var caster := _ally("u1")
	var ally := _ally("u2")
	ally.hp = ally.max_hp - 5
	var bc := HealBroadcaster.new()
	var captured := _capture(bc)
	var spell := Spell.make("h", "Smart Heal", Spell.EffectKind.SMART_HEAL, 3, 1.0)
	SpellEffectResolver.apply(spell, caster, [ally], null, null, "u1", bc)
	assert_eq(captured.size(), 1)
	assert_eq(captured[0][0], "u1")
	assert_eq(captured[0][1], "u2")
	assert_eq(captured[0][2], "SMART_HEAL")


func test_resolver_emits_per_target_for_aoe_heal():
	var caster := _ally("u1")
	var a := _ally("u2")
	var b := _ally("u3")
	a.hp = 1
	b.hp = 1
	var bc := HealBroadcaster.new()
	var captured := _capture(bc)
	var spell := Spell.make("h", "AOE Heal", Spell.EffectKind.AOE_HEAL, 4, 1.0)
	SpellEffectResolver.apply(spell, caster, [a, b], null, null, "u1", bc)
	assert_eq(captured.size(), 2, "one emission per target")
	assert_eq(captured[0][1], "u2")
	assert_eq(captured[1][1], "u3")
	assert_eq(captured[0][2], "AOE_HEAL")


func test_resolver_emits_for_group_regen():
	var caster := _ally("u1")
	var ally := _ally("u2")
	var bc := HealBroadcaster.new()
	var captured := _capture(bc)
	var spell := Spell.make("g", "Regen Snooze", Spell.EffectKind.GROUP_REGEN, 0, 3.0)
	SpellEffectResolver.apply(spell, caster, [ally], null, null, "u1", bc)
	assert_eq(captured.size(), 1)
	assert_eq(captured[0][2], "GROUP_REGEN")
	assert_eq(captured[0][3], 2, "2 HP/sec tick rate")
	assert_eq(captured[0][4], 15.0, "15s duration")


func test_resolver_emits_two_for_party_buff():
	# PARTY_BUFF bundles defense + magic_resistance — two emissions
	# per target keeps the wire 1:1 with the local add_buff calls.
	var caster := _ally("u1")
	var ally := _ally("u2")
	var bc := HealBroadcaster.new()
	var captured := _capture(bc)
	var spell := Spell.make("p", "Cozy Aura", Spell.EffectKind.PARTY_BUFF, 0, 4.0)
	SpellEffectResolver.apply(spell, caster, [ally], null, null, "u1", bc)
	assert_eq(captured.size(), 2, "defense + magic_resistance = 2 emissions")
	assert_eq(captured[0][2], "PARTY_BUFF_DEFENSE")
	assert_eq(captured[1][2], "PARTY_BUFF_MAGIC_RESISTANCE")
	assert_eq(captured[0][3], 3)
	assert_eq(captured[1][3], 3)


func test_resolver_no_crash_without_broadcaster():
	# Nil-safe: solo / pre-handshake / test paths pass null and the
	# resolver must still apply effects without touching the broadcaster.
	var caster := _ally("u1")
	var ally := _ally("u2")
	ally.hp = ally.max_hp - 3
	var spell := Spell.make("h", "Smart Heal", Spell.EffectKind.SMART_HEAL, 5, 1.0)
	var healed := SpellEffectResolver.apply(spell, caster, [ally], null, null, "u1", null)
	assert_true(healed > 0, "heal still applies without a broadcaster")
