class_name MushroomEffect
extends PowerUpEffect

# +30% defense for 6 seconds. Stores the additive delta so a level-up
# during the buff doesn't get clobbered when the effect drops off — only
# the bonus we applied is removed.

const DEFENSE_BONUS_PCT := 0.30
const DURATION := 6.0

var _applied_defense_bonus: int = 0

func _init() -> void:
	type = PowerUpEffect.TYPE_MUSHROOMS
	duration = DURATION
	remaining = DURATION

func _on_apply(target) -> void:
	var base: int = int(target.defense)
	var bonus: int = int(round(base * DEFENSE_BONUS_PCT))
	if bonus < 1:
		bonus = 1
	_applied_defense_bonus = bonus
	target.defense = base + bonus

func _on_remove(target) -> void:
	target.defense = int(target.defense) - _applied_defense_bonus
	_applied_defense_bonus = 0
