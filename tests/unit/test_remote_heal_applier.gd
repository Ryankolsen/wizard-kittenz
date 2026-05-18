extends GutTest

# Tests for RemoteHealApplier — the inbound-from-wire counterpart to
# HealBroadcaster (PRD #140, issue #146). Sibling-shaped to
# RemoteTauntApplier: SceneTree group walk on "players", duck-typed
# read of {data, player_id} so a lightweight Node stub stands in for
# a full Player CharacterBody2D in tests (avoids dragging Player._ready's
# whole boot path into the test fixture).

class _StubPlayer:
	extends Node
	var data: CharacterData = null
	var player_id: String = ""

func _make_player_in_tree(pid: String) -> _StubPlayer:
	var p := _StubPlayer.new()
	p.player_id = pid
	p.data = CharacterData.make_new(CharacterData.CharacterClass.SLEEPY_KITTEN, "k")
	p.data.player_id = pid
	# Drop HP so heal() has headroom to restore — heal() clamps to max_hp.
	p.data.hp = p.data.max_hp - 5
	p.add_to_group("players")
	add_child_autofree(p)
	return p

func test_apply_returns_false_on_null_tree():
	assert_false(RemoteHealApplier.apply(null, "u1", "AOE_HEAL", 5, 0.0))

func test_apply_returns_false_on_empty_effect_kind():
	# Forward-compat guard: an unkeyed packet can't be dispatched. The
	# routing layer drops this earlier but the applier backstops it.
	_make_player_in_tree("u1")
	assert_false(RemoteHealApplier.apply(get_tree(), "u1", "", 5, 0.0))

func test_apply_returns_false_on_unknown_effect_kind():
	# A future EffectKind a stale client doesn't recognize must not crash
	# (mismatched-version safety) and must not silently fall through to
	# heal() with the wrong amount.
	_make_player_in_tree("u1")
	assert_false(RemoteHealApplier.apply(get_tree(), "u1", "MYSTERY_HEAL", 5, 0.0))

func test_apply_returns_false_on_no_matching_player():
	# Player already left / never spawned locally — the applier walks
	# the group, finds no match, returns false. No crash.
	_make_player_in_tree("u1")
	assert_false(RemoteHealApplier.apply(get_tree(), "u99", "AOE_HEAL", 5, 0.0))

func test_smart_heal_restores_hp_on_matched_player():
	var p := _make_player_in_tree("u1")
	var before := p.data.hp
	assert_true(RemoteHealApplier.apply(get_tree(), "u1", "SMART_HEAL", 5, 0.0))
	assert_eq(p.data.hp, before + 5, "SMART_HEAL restores HP via data.heal")

func test_aoe_heal_restores_hp_on_matched_player():
	var p := _make_player_in_tree("u1")
	var before := p.data.hp
	assert_true(RemoteHealApplier.apply(get_tree(), "u1", "AOE_HEAL", 4, 0.0))
	assert_eq(p.data.hp, before + 4)

func test_aoe_heal_with_empty_target_id_heals_all_players():
	# AOE / party-wide sentinel: target_id == "" applies to every player
	# in the group. Acceptance criterion from issue #146.
	var p1 := _make_player_in_tree("u1")
	var p2 := _make_player_in_tree("u2")
	var b1 := p1.data.hp
	var b2 := p2.data.hp
	assert_true(RemoteHealApplier.apply(get_tree(), "", "AOE_HEAL", 3, 0.0))
	assert_eq(p1.data.hp, b1 + 3, "all players in group healed under AOE sentinel")
	assert_eq(p2.data.hp, b2 + 3)

func test_smart_heal_only_heals_matching_target():
	# Targeted heal must surgically apply to the matching player only.
	var p1 := _make_player_in_tree("u1")
	var p2 := _make_player_in_tree("u2")
	var b2 := p2.data.hp
	assert_true(RemoteHealApplier.apply(get_tree(), "u1", "SMART_HEAL", 5, 0.0))
	assert_eq(p2.data.hp, b2, "non-matching player left untouched")

func test_group_regen_applies_buff():
	# GROUP_REGEN routes through the active-buff system: the HoT sentinel
	# stat is BUFF_GROUP_REGEN, and tick_buffs heals over time. Here we
	# just assert the buff is active (the tick path is covered in
	# test_active_buff).
	var p := _make_player_in_tree("u1")
	assert_true(RemoteHealApplier.apply(get_tree(), "u1", "GROUP_REGEN", 2, 15.0))
	assert_true(p.data.has_active_buff(CharacterData.BUFF_GROUP_REGEN))

func test_party_buff_defense_applies_buff():
	# PARTY_BUFF_DEFENSE adds +amount to the defense field for duration.
	# Mirrors the local resolver's add_buff("defense", ...) call so the
	# wire stays 1:1 with the local cast path.
	var p := _make_player_in_tree("u1")
	var before := p.data.defense
	assert_true(RemoteHealApplier.apply(get_tree(), "u1", "PARTY_BUFF_DEFENSE", 3, 15.0))
	assert_eq(p.data.defense, before + 3, "defense raised by buff amount")
	assert_true(p.data.has_active_buff("defense"))

func test_party_buff_magic_resistance_applies_buff():
	# Sibling of PARTY_BUFF_DEFENSE — same shape, different stat field.
	# Two emissions per Cozy Aura cast (defense + MR) — each handled
	# independently here so the receiver doesn't need to know the bundle.
	var p := _make_player_in_tree("u1")
	var before := p.data.magic_resistance
	assert_true(RemoteHealApplier.apply(get_tree(), "u1", "PARTY_BUFF_MAGIC_RESISTANCE", 3, 15.0))
	assert_eq(p.data.magic_resistance, before + 3)
	assert_true(p.data.has_active_buff("magic_resistance"))

func test_apply_skips_player_with_null_data():
	# Defensive: a Player node added to the group before _ready finished
	# wiring up data. Skip it rather than crash on null .data access.
	var bare := _StubPlayer.new()
	bare.player_id = "u1"
	bare.data = null
	bare.add_to_group("players")
	add_child_autofree(bare)
	var target := _make_player_in_tree("u2")
	var before := target.data.hp
	assert_true(RemoteHealApplier.apply(get_tree(), "", "AOE_HEAL", 3, 0.0))
	assert_eq(target.data.hp, before + 3)

func test_apply_zero_amount_smart_heal_returns_false():
	# A SMART_HEAL emitted with amount=0 (full-HP target on the sender)
	# is a no-op on the receiver too — heal(0) returns 0, but we report
	# the no-op via false so a future caller observing the rising-edge
	# return (e.g. logging) doesn't over-count.
	_make_player_in_tree("u1")
	assert_false(RemoteHealApplier.apply(get_tree(), "u1", "SMART_HEAL", 0, 0.0))

func test_aoe_heal_empty_target_returns_false_when_no_players():
	# Sentinel + empty group is still a no-op — no players to fan out to.
	assert_false(RemoteHealApplier.apply(get_tree(), "", "AOE_HEAL", 5, 0.0))
