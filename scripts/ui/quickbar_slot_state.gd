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

const _GWENDOLYN_SPELL_ID := "summon_gwendolyn"

# Returns a dict with:
#   empty:             bool — true when slot has no spell
#   disabled:          bool — empty, cooldown, or insufficient MP
#   cooldown_fraction: float — 0..1 portion of cooldown remaining (0.0 ready)
#   show_mp_badge:     bool — true when spell.mp_cost > 0
#   mp_cost:           int  — spell.mp_cost (or 0 when empty)
#   reason:            String — REASON_* constant explaining disabled state
#
# gwendolyn_last_used/now_unix (issue #477 follow-up): Summon Gwendolyn's real
# gate is GwendolynCooldown's hourly real-world timer, not spell.cooldown (a
# short in-run value that only exists so the cast-channel path has *a*
# cooldown to tick). Without this, the icon read spell.cooldown_remaining and
# looked ready seconds after casting even though fire_slot() was still
# blocking the recast for the rest of the hour. now_unix < 0 reads the system
# clock; tests pass a fixed value for deterministic assertions.
static func derive(spell: Spell, caster, gwendolyn_last_used = null, now_unix: int = -1) -> Dictionary:
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
	if spell.id == _GWENDOLYN_SPELL_ID and gwendolyn_last_used != null:
		var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
		var remaining := GwendolynCooldown.time_remaining(gwendolyn_last_used, now)
		var gwendolyn_fraction := clampf(float(remaining) / float(GwendolynCooldown.COOLDOWN_SECONDS), 0.0, 1.0)
		fraction = maxf(fraction, gwendolyn_fraction)
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
