class_name MushroomEffect
extends PowerUpEffect

# Random spell fires every 2 seconds for 6 seconds. Doesn't mutate stats —
# the visual chaos is the point. Emits `random_spell_fired` once per
# FIRE_INTERVAL accumulated; an external listener (Player) handles the
# actual spell pick + cast.
#
# Accumulator-style ticking handles arbitrary dt — a single tick(2.0)
# emits once, three tick(2.0) emits three times, and many small ticks
# summing to 2.0 emit once. The while-loop drains multi-emission cases
# so a tick(4.0) emits twice rather than dropping one.

signal random_spell_fired

const DURATION := 6.0
const FIRE_INTERVAL := 2.0

var _interval_accum: float = 0.0

func _init() -> void:
	type = PowerUpEffect.TYPE_MUSHROOMS
	duration = DURATION
	remaining = DURATION

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	super.tick(dt)
	_interval_accum += dt
	while _interval_accum >= FIRE_INTERVAL:
		_interval_accum -= FIRE_INTERVAL
		random_spell_fired.emit()
