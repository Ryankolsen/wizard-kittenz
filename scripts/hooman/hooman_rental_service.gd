class_name HoomanRentalService
extends RefCounted

# Owns rental state for the hired hooman companion (PRD #491): whether it's
# paid-for-and-active on the current floor, and the flat gold cost to
# activate it. Session-agnostic — the solo-only gate lives in the caller
# (Bartender's enabled_predicate), not here. Same style as CurrencyLedger /
# NPCOption: pure RefCounted, no SceneTree.

const RENT_COST_GOLD: int = 25

var _active_floor: int = -1

# Debits RENT_COST_GOLD gold from ledger and records floor_number as paid.
# Returns false and leaves state untouched if the debit fails.
func activate(floor_number: int, ledger: CurrencyLedger) -> bool:
	if not ledger.debit(RENT_COST_GOLD, CurrencyLedger.Currency.GOLD):
		return false
	_active_floor = floor_number
	return true

# True only if activate() succeeded for this exact floor number.
func is_active_for_floor(floor_number: int) -> bool:
	return _active_floor == floor_number

# Resets paid state so is_active_for_floor() returns false for every floor
# until activate() is called again. Used by floor transition and by
# hooman-defeat handling.
func clear() -> void:
	_active_floor = -1
