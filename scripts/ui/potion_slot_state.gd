class_name PotionSlotState
extends RefCounted

# Slice 7 of PRD #358. Pure helper that derives per-slot render state for the
# PotionBeltHUD from (potion_def, count, cooldown_fraction). Extracted so the
# empty / disabled / cooldown_fraction / uses_texture / reason decisions are
# unit-testable without instancing a Control tree. Mirrors QuickbarSlotState.
#
# Cooldown is passed in as a 0..1 fraction rather than re-derived here: the
# belt owns the single shared cooldown across all three slots (slice 4), so
# the HUD computes the fraction once and feeds it to every slot — keeping the
# helper input-pure and free of any PotionBelt dependency.

const REASON_EMPTY := "empty"
const REASON_OUT_OF_STOCK := "out_of_stock"
const REASON_COOLDOWN := "cooldown"
const REASON_READY := "ready"

# Returns a dict with:
#   empty:             bool — true when slot has no potion assigned
#   disabled:          bool — empty, 0-count, or on cooldown
#   count:             int  — current ConsumableInventory count for this id
#   cooldown_fraction: float — 0..1 portion of shared cooldown remaining
#   uses_texture:      bool — true when def.icon is set (else placeholder)
#   reason:            String — REASON_* constant explaining the state
static func derive(slot_def: PotionDefinition, count: int, cooldown_fraction: float) -> Dictionary:
	if slot_def == null:
		return {
			"empty": true,
			"disabled": true,
			"count": 0,
			"cooldown_fraction": 0.0,
			"uses_texture": false,
			"reason": REASON_EMPTY,
		}
	var fraction := clampf(cooldown_fraction, 0.0, 1.0)
	var on_cooldown := fraction > 0.0
	var out_of_stock := count <= 0
	var disabled := on_cooldown or out_of_stock
	var reason := REASON_READY
	if out_of_stock:
		reason = REASON_OUT_OF_STOCK
	elif on_cooldown:
		reason = REASON_COOLDOWN
	return {
		"empty": false,
		"disabled": disabled,
		"count": count,
		"cooldown_fraction": fraction,
		"uses_texture": slot_def.icon != null,
		"reason": reason,
	}
