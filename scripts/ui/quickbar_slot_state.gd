class_name QuickbarSlotState
extends RefCounted

# Slice 3 of PRD #210. Pure helper that derives per-slot render state for
# the QuickbarHUD from (spell, caster). Extracted from the HUD so the
# empty / disabled / cooldown_fraction / show_mp_badge / reason decisions
# are unit-testable without instancing a Control tree.

const REASON_EMPTY := "empty"
const REASON_COOLDOWN := "cooldown"
const REASON_MP := "mp"
const REASON_READY := "ready"

# Returns a dict with:
#   empty:             bool — true when slot has no spell
#   disabled:          bool — empty, cooldown, or insufficient MP
#   cooldown_fraction: float — 0..1 portion of cooldown remaining (0.0 ready)
#   show_mp_badge:     bool — true when spell.mp_cost > 0
#   mp_cost:           int  — spell.mp_cost (or 0 when empty)
#   reason:            String — REASON_* constant explaining disabled state
static func derive(spell: Spell, caster) -> Dictionary:
	if spell == null:
		return {
			"empty": true,
			"disabled": true,
			"cooldown_fraction": 0.0,
			"show_mp_badge": false,
			"mp_cost": 0,
			"reason": REASON_EMPTY,
		}
	var fraction := 0.0
	if spell.cooldown > 0.0 and spell.cooldown_remaining > 0.0:
		fraction = clampf(spell.cooldown_remaining / spell.cooldown, 0.0, 1.0)
	var on_cooldown := fraction > 0.0
	var mp_short := false
	if spell.mp_cost > 0 and caster != null and "magic_points" in caster:
		mp_short = caster.magic_points < spell.mp_cost
	var disabled := on_cooldown or mp_short
	var reason := REASON_READY
	if on_cooldown:
		reason = REASON_COOLDOWN
	elif mp_short:
		reason = REASON_MP
	return {
		"empty": false,
		"disabled": disabled,
		"cooldown_fraction": fraction,
		"show_mp_badge": spell.mp_cost > 0,
		"mp_cost": spell.mp_cost,
		"reason": reason,
	}
