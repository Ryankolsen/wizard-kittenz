class_name Health
extends Resource

@export var current: int = 10
@export var maximum: int = 10
@export var defense: int = 0

static func make(maximum_val: int, defense_val: int = 0) -> Health:
	var h := Health.new()
	h.maximum = maximum_val
	h.current = maximum_val
	h.defense = defense_val
	return h

func is_alive() -> bool:
	return current > 0

func take_damage(amount: int) -> int:
	var dealt := mini(amount, current)
	current -= dealt
	return dealt

func heal(amount: int) -> int:
	var healed := mini(amount, maximum - current)
	current += healed
	return healed
