extends GutTest

# Slice 3 of PRD #210. QuickbarSlotState.derive(slot_spell, caster) is the
# pure helper that drives the HUD's per-slot render — extracted from the
# scene so the disabled / cooldown_fraction / show_mp_badge / reason
# decisions are testable without instancing a Control tree.

func _spell(name: String, kind: int, cd: float, mp_cost: int) -> Spell:
	return Spell.make("s_" + name, name, kind, 1, cd, 0, mp_cost)

class _StubCaster:
	var magic_points: int = 100
	var max_mp: int = 100

func test_empty_slot_state_is_empty_disabled():
	var state := QuickbarSlotState.derive(null, null)
	assert_true(state["empty"], "empty slot must report empty=true")
	assert_true(state["disabled"], "empty slot must be disabled")
	assert_eq(state["reason"], QuickbarSlotState.REASON_EMPTY)

func test_on_cooldown_state_has_remaining_fraction():
	var s := _spell("Hairball Hex", Spell.EffectKind.DAMAGE, 2.0, 0)
	s.cooldown_remaining = 1.0
	var caster := _StubCaster.new()
	var state := QuickbarSlotState.derive(s, caster)
	assert_true(state["disabled"], "on cooldown must be disabled")
	assert_almost_eq(state["cooldown_fraction"], 0.5, 0.01)
	assert_eq(state["reason"], QuickbarSlotState.REASON_COOLDOWN)

func test_insufficient_mp_state_is_disabled():
	var s := _spell("Whisker Bolt", Spell.EffectKind.DAMAGE, 1.0, 8)
	var caster := _StubCaster.new()
	caster.magic_points = 3
	var state := QuickbarSlotState.derive(s, caster)
	assert_true(state["disabled"], "insufficient MP must be disabled")
	assert_eq(state["reason"], QuickbarSlotState.REASON_MP)

func test_ready_state_not_disabled():
	var s := _spell("Hairball Hex", Spell.EffectKind.DAMAGE, 1.0, 5)
	var caster := _StubCaster.new()
	caster.magic_points = 10
	var state := QuickbarSlotState.derive(s, caster)
	assert_false(state["empty"])
	assert_false(state["disabled"])
	assert_eq(state["cooldown_fraction"], 0.0)
	assert_eq(state["reason"], QuickbarSlotState.REASON_READY)

func test_state_hides_mp_badge_when_cost_zero():
	var s := _spell("Tail Whip", Spell.EffectKind.DAMAGE, 1.0, 0)
	var caster := _StubCaster.new()
	var state := QuickbarSlotState.derive(s, caster)
	assert_false(state["show_mp_badge"], "mp_cost=0 must suppress MP badge")
	assert_eq(state["mp_cost"], 0)

func test_state_shows_mp_badge_when_cost_positive():
	var s := _spell("Hairball Hex", Spell.EffectKind.DAMAGE, 1.0, 5)
	var caster := _StubCaster.new()
	var state := QuickbarSlotState.derive(s, caster)
	assert_true(state["show_mp_badge"], "mp_cost>0 must show MP badge")
	assert_eq(state["mp_cost"], 5)
