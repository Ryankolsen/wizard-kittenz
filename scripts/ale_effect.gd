class_name AleEffect
extends PowerUpEffect

# +30% attack damage for 10 seconds. The bonus is rounded to int so the
# attack field stays integer-typed; `max(1, ...)` ensures the bonus is
# always meaningful even at low base attack (Mage's attack 2 -> +1).
#
# get_movement_offset is a pure static read of the wobble offset for the
# given time — render code calls it each frame to add a sinusoidal sway
# to the player's visual.

const ATTACK_BONUS_PCT := 0.30
const DURATION := 10.0
const WOBBLE_AMPLITUDE := 4.0
const WOBBLE_FREQUENCY := 6.0

var _applied_attack_bonus: int = 0

func _init() -> void:
	type = PowerUpEffect.TYPE_ALE
	duration = DURATION
	remaining = DURATION

func _on_apply(target) -> void:
	var base: int = int(target.attack)
	var bonus: int = int(round(base * ATTACK_BONUS_PCT))
	if bonus < 1:
		bonus = 1
	_applied_attack_bonus = bonus
	target.attack = base + bonus

func _on_remove(target) -> void:
	target.attack = int(target.attack) - _applied_attack_bonus
	_applied_attack_bonus = 0

# Sinusoidal wobble offset. Two-axis with different frequencies so it reads
# as drunken sway rather than a clean horizontal slide. Pure function so
# tests can assert variance over `time` without setup state.
static func get_movement_offset(time: float) -> Vector2:
	var x := sin(time * WOBBLE_FREQUENCY) * WOBBLE_AMPLITUDE
	var y := sin(time * WOBBLE_FREQUENCY * 0.5) * WOBBLE_AMPLITUDE * 0.5
	return Vector2(x, y)
