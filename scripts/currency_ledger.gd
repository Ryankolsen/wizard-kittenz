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
