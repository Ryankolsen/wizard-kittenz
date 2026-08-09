extends GutTest

# Slice 1 of PRD #210: Quickbar data class + InputMap cast_slot_1..cast_slot_4.

const _KEY_1 := 49
const _KEY_Q := 81
const _KEY_F := 70

func _wizard_tree() -> SkillTree:
	return SkillTree.make_wizard_kitten_tree()

func _spell(tree: SkillTree, id: String) -> Spell:
	return tree.find(id).spell

func test_assign_places_spell_in_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var hairball := _spell(tree, "hairball_hex")
	qb.assign(1, hairball)
	assert_eq(qb.get_slot(1), hairball)

func test_assign_same_spell_to_new_slot_swaps():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	qb.assign(1, a)
	qb.assign(2, a)
	assert_null(qb.get_slot(1))
	assert_eq(qb.get_slot(2), a)

func test_assign_over_occupied_slot_swaps_occupants():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	var b := _spell(tree, "catnip_curse")
	qb.assign(1, a)
	qb.assign(2, b)
	qb.assign(2, a)
	assert_eq(qb.get_slot(1), b)
	assert_eq(qb.get_slot(2), a)

func test_unassign_clears_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	qb.assign(1, a)
	qb.unassign(1)
	assert_null(qb.get_slot(1))

func test_on_spell_unlocked_fills_lowest_empty_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	var b := _spell(tree, "catnip_curse")
	qb.assign(1, a)
	qb.on_spell_unlocked(b)
	assert_eq(qb.get_slot(2), b)

func test_on_spell_unlocked_noop_when_full():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	qb.assign(1, _spell(tree, "hairball_hex"))
	qb.assign(2, _spell(tree, "catnip_curse"))
	qb.assign(3, _spell(tree, "whisker_bolt"))
	qb.assign(4, _spell(tree, "litter_storm"))
	var arcane := _spell(tree, "arcane_purr")
	qb.on_spell_unlocked(arcane)
	for i in range(1, Quickbar.SLOT_COUNT + 1):
		assert_ne(qb.get_slot(i), arcane)

func test_on_spell_unlocked_noop_when_already_in_slot():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	qb.assign(2, a)
	qb.on_spell_unlocked(a)
	assert_null(qb.get_slot(1))
	assert_eq(qb.get_slot(2), a)
	assert_null(qb.get_slot(3))
	assert_null(qb.get_slot(4))

func test_fire_slot_empty_returns_false():
	var qb := Quickbar.new()
	watch_signals(qb)
	assert_false(qb.fire_slot(1, null))
	assert_signal_not_emitted(qb, "slot_fired")

func test_fire_slot_calls_spell_cast():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	# Make MP cost trivially affordable: the spell carries mp_cost > 0, give a
	# caster with enough magic_points so cast() succeeds.
	var caster := _StubCaster.new()
	caster.magic_points = 999
	caster.hp = 999
	qb.assign(1, a)
	watch_signals(qb)
	assert_true(qb.fire_slot(1, caster))
	assert_signal_emitted_with_parameters(qb, "slot_fired", [1])

# --- Cast-channel wiring (issue #476) ---

func _channeled_spell(cast_time: float = 15.0) -> Spell:
	var s := Spell.make("channeled_test_spell", "Channeled Test Spell", Spell.EffectKind.BUFF, 0, 1.0)
	s.cast_time = cast_time
	return s

func test_fire_slot_with_cast_time_starts_channel_without_casting_yet():
	var qb := Quickbar.new()
	var spell := _channeled_spell()
	qb.assign(1, spell)
	watch_signals(qb)
	assert_true(qb.fire_slot(1, null), "starting a channel is itself a successful input")
	assert_true(qb.is_channeling())
	assert_eq(spell.cooldown_remaining, 0.0, "cooldown must not be consumed until the channel completes")
	assert_signal_not_emitted(qb, "slot_fired")
	assert_signal_emitted_with_parameters(qb, "channel_started", [1])

func test_channel_tick_to_completion_casts_and_emits_slot_fired():
	var qb := Quickbar.new()
	var spell := _channeled_spell(15.0)
	qb.assign(1, spell)
	qb.fire_slot(1, null)
	watch_signals(qb)
	qb.tick(15.0)
	assert_false(qb.is_channeling())
	assert_gt(spell.cooldown_remaining, 0.0, "cooldown is consumed only on channel completion")
	assert_signal_emitted_with_parameters(qb, "slot_fired", [1])
	assert_signal_emitted_with_parameters(qb, "channel_completed", [1])

func test_channel_partial_tick_does_not_cast():
	var qb := Quickbar.new()
	var spell := _channeled_spell(15.0)
	qb.assign(1, spell)
	qb.fire_slot(1, null)
	watch_signals(qb)
	qb.tick(10.0)
	assert_true(qb.is_channeling())
	assert_signal_not_emitted(qb, "slot_fired")

func test_on_damage_taken_cancels_channel_without_consuming_cooldown():
	var qb := Quickbar.new()
	var spell := _channeled_spell(15.0)
	qb.assign(1, spell)
	qb.fire_slot(1, null)
	qb.tick(5.0)
	watch_signals(qb)
	qb.on_damage_taken()
	assert_false(qb.is_channeling())
	assert_eq(spell.cooldown_remaining, 0.0, "an interrupted channel must not consume a cooldown")
	assert_signal_emitted_with_parameters(qb, "channel_cancelled", [1])
	# Retry is immediate: no penalty, no lockout.
	assert_true(qb.fire_slot(1, null), "an interrupted cast can be retried immediately")

func test_fire_slot_is_blocked_while_another_channel_is_active():
	var qb := Quickbar.new()
	var a := _channeled_spell(15.0)
	var b := _channeled_spell(15.0)
	b.id = "channeled_test_spell_2"
	qb.assign(1, a)
	qb.assign(2, b)
	qb.fire_slot(1, null)
	assert_false(qb.fire_slot(2, null), "a second cast cannot start while a channel is active")

func test_instant_spell_cast_time_zero_is_unaffected_by_channel_logic():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	assert_eq(a.cast_time, 0.0, "existing spells default to instant cast")
	var caster := _StubCaster.new()
	caster.magic_points = 999
	caster.hp = 999
	qb.assign(1, a)
	assert_true(qb.fire_slot(1, caster))
	assert_false(qb.is_channeling(), "an instant cast never enters the channeling state")

func test_serialize_deserialize_preserves_assignments():
	var tree := _wizard_tree()
	var qb := Quickbar.new()
	var a := _spell(tree, "hairball_hex")
	var c := _spell(tree, "whisker_bolt")
	qb.assign(1, a)
	qb.assign(3, c)
	var dict := qb.serialize()
	var fresh_tree := _wizard_tree()
	var qb2 := Quickbar.new()
	qb2.deserialize(dict, fresh_tree)
	assert_eq(qb2.get_slot(1).id, "hairball_hex")
	assert_null(qb2.get_slot(2))
	assert_eq(qb2.get_slot(3).id, "whisker_bolt")
	assert_null(qb2.get_slot(4))

# --- Gwendolyn hourly cooldown gating (issue #477) ---

func _gwendolyn_spell() -> Spell:
	var s := Spell.make("summon_gwendolyn", "Summon Gwendolyn", Spell.EffectKind.BUFF, 0, 15.0)
	s.cast_time = 15.0
	return s

func test_fire_slot_blocked_while_gwendolyn_on_cooldown():
	var qb := Quickbar.new()
	var spell := _gwendolyn_spell()
	qb.assign(1, spell)
	var now := 100000
	qb.gwendolyn_last_summon_unix = now - 1800
	watch_signals(qb)
	assert_false(qb.fire_slot(1, null, now))
	assert_false(qb.is_channeling())
	assert_signal_not_emitted(qb, "channel_started")

func test_fire_slot_allowed_once_gwendolyn_cooldown_expires():
	var qb := Quickbar.new()
	var spell := _gwendolyn_spell()
	qb.assign(1, spell)
	var now := 100000
	qb.gwendolyn_last_summon_unix = now - 3700
	assert_true(qb.fire_slot(1, null, now))
	assert_true(qb.is_channeling())

func test_completed_gwendolyn_channel_starts_cooldown():
	var qb := Quickbar.new()
	var spell := _gwendolyn_spell()
	qb.assign(1, spell)
	var now := 100000
	assert_eq(qb.gwendolyn_last_summon_unix, 0)
	qb.fire_slot(1, null, now)
	qb.tick(15.0, now)
	assert_eq(qb.gwendolyn_last_summon_unix, now)

func test_cancelled_gwendolyn_channel_does_not_start_cooldown():
	var qb := Quickbar.new()
	var spell := _gwendolyn_spell()
	qb.assign(1, spell)
	var now := 100000
	qb.fire_slot(1, null, now)
	qb.tick(5.0, now)
	qb.on_damage_taken()
	assert_eq(qb.gwendolyn_last_summon_unix, 0, "interrupted cast must not start the cooldown")

func test_inputmap_has_cast_slot_actions():
	for i in range(1, 5):
		var name := "cast_slot_%d" % i
		assert_true(InputMap.has_action(name), "InputMap missing %s" % name)
	var keys := {}
	for ev in InputMap.action_get_events("cast_slot_1"):
		if ev is InputEventKey:
			keys[ev.keycode] = true
	assert_true(keys.has(_KEY_1), "cast_slot_1 missing key 1")
	assert_true(keys.has(_KEY_Q), "cast_slot_1 missing key Q")
	assert_true(keys.has(_KEY_F), "cast_slot_1 missing key F")

class _StubCaster:
	var magic_points: int = 0
	var hp: int = 100
