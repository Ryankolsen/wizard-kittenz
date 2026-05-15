class_name CatnipEffect
extends PowerUpEffect

# +50% move speed for 8 seconds. Stores the additive delta so a level-up
# during the buff doesn't get clobbered when the effect drops off — only
# the bonus we applied is removed.

const SPEED_MULTIPLIER := 1.5
const DURATION := 8.0

var _applied_speed_bonus: float = 0.0

func _init() -> void:
	type = PowerUpEffect.TYPE_CATNIP
	duration = DURATION
	remaining = DURATION

func _on_apply(target) -> void:
	var base: float = float(target.speed)
	_applied_speed_bonus = base * (SPEED_MULTIPLIER - 1.0)
	target.speed = base + _applied_speed_bonus

func _on_remove(target) -> void:
	target.speed = float(target.speed) - _applied_speed_bonus
	_applied_speed_bonus = 0.0
