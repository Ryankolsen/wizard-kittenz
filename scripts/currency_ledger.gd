class_name CurrencyLedger
extends RefCounted

# Owns Gold and Gem balances (PRD #53). Balances cannot go below zero —
# debit returns false when the requested amount exceeds the balance and
# leaves the balance untouched. Every successful mutation emits
# balance_changed so HUD / ShopScreen can react without polling.

enum Currency { GOLD, GEM }

signal balance_changed(currency: int, new_balance: int)

var _balances: Dictionary = {
	Currency.GOLD: 0,
	Currency.GEM: 0,
}

# Session-scoped replay guard for consumable Gem bundle IAPs (PRD #53 / #69).
# BillingManager replays purchase_succeeded for unconsumed tokens on startup;
# without this set a second-firing wire packet would credit the bundle twice
# before the consume-acknowledge round-trips. Not persisted to disk — once
# the token is consumed against Play Billing, the same product_id can be
# re-purchased in a future session and credit again.
var _granted_bundle_ids: Array = []

func balance(currency: int) -> int:
	return int(_balances.get(currency, 0))

func credit(amount: int, currency: int) -> void:
	if amount <= 0:
		return
	_balances[currency] = balance(currency) + amount
	balance_changed.emit(currency, _balances[currency])

func debit(amount: int, currency: int) -> bool:
	if amount <= 0:
		return false
	var current := balance(currency)
	if amount > current:
		return false
	_balances[currency] = current - amount
	balance_changed.emit(currency, _balances[currency])
	return true

# Credits a Gem bundle exactly once per (ledger, product_id). Returns true iff
# the bundle was newly granted on this call; false on a replay. The replay
# guard is co-located with the credit op so the "did this bundle pay out?"
# question lives next to the balance it pays into.
func try_grant_bundle(product_id: String, gem_amount: int) -> bool:
	if product_id == "" or gem_amount <= 0:
		return false
	if _granted_bundle_ids.has(product_id):
		return false
	_granted_bundle_ids.append(product_id)
	credit(gem_amount, Currency.GEM)
	return true
