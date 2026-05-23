class_name NPCOption
extends RefCounted

# Issue #195: a single row in an NPC interaction menu (speech bubble).
#
# Pure data — no scene tree, no UI, no input. The bubble UI renders one row
# per option and dispatches the chosen option's effect_id back to the NPC
# script. Availability (e.g. affordability) is computed lazily via the
# is_enabled Callable so the answer reflects gold/state at bubble-open time,
# not whatever was true when the option was constructed.

enum CurrencyType { NONE, GOLD, GEMS }

var label: String = ""
var effect_id: String = ""
var cost_currency: int = CurrencyType.NONE
var cost_amount: int = 0
# Callable that returns bool. If null, the option is always enabled.
var enabled_predicate: Callable = Callable()


static func make(label_text: String, effect: String, predicate: Callable = Callable(), currency: int = CurrencyType.NONE, amount: int = 0) -> NPCOption:
	var o := NPCOption.new()
	o.label = label_text
	o.effect_id = effect
	o.enabled_predicate = predicate
	o.cost_currency = currency
	o.cost_amount = amount
	return o


func is_enabled() -> bool:
	if not enabled_predicate.is_valid():
		return true
	return bool(enabled_predicate.call())
