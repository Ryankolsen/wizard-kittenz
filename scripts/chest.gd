class_name Chest
extends RefCounted

# Single-use loot container (PRD #53 / issue #66). A chest has a kind
# (STANDARD = Gold, RARE = Gem); open(ledger) credits the configured
# amount once and flips _opened so a second call is a no-op. World-
# entity wrapping (Area2D, sprite, interact prompt) lands in the
# scene/world layer in a later slice — this is the pure-data core
# that ShopScreen-side tests and dungeon spawning can both build on.

enum Kind { STANDARD, RARE }

const STANDARD_GOLD: int = 25
const RARE_GEMS: int = 5

var kind: int = Kind.STANDARD
var _opened: bool = false

static func make(p_kind: int) -> Chest:
	var c := Chest.new()
	c.kind = p_kind
	return c

func is_opened() -> bool:
	return _opened

# Credits the configured currency to `ledger` and marks the chest used.
# Returns true on the first successful open, false on every later call
# or when `ledger` is null. Same idempotence shape as the per-kill
# Gold credit in KillRewardRouter — re-firing the open signal can't
# pay out twice.
func open(ledger: CurrencyLedger) -> bool:
	if _opened:
		return false
	if ledger == null:
		return false
	match kind:
		Kind.STANDARD:
			ledger.credit(STANDARD_GOLD, CurrencyLedger.Currency.GOLD)
		Kind.RARE:
			ledger.credit(RARE_GEMS, CurrencyLedger.Currency.GEM)
		_:
			return false
	_opened = true
	return true
