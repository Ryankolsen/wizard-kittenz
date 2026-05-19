class_name WetEffect
extends PowerUpEffect

# -30% move speed for `duration` seconds (issue #160). Same delta-tracking
# pattern as CatnipEffect — store the subtracted delta so a level-up during
# the debuff isn't clobbered on expiry. Spawners pass a custom duration so
# different sources (water-cone vs. puddle) can tune.

const TYPE := "wet"
const DEFAULT_DURATION := 4.0
const SPEED_PENALTY_PCT := 0.30

var _applied_speed_delta: float = 0.0

func _init(duration_seconds: float = DEFAULT_DURATION) -> void:
	type = TYPE
	duration = duration_seconds
	remaining = duration_seconds

func _on_apply(target) -> void:
	var base: float = float(target.speed)
	_applied_speed_delta = base * SPEED_PENALTY_PCT
	target.speed = base - _applied_speed_delta

func _on_remove(target) -> void:
	target.speed = float(target.speed) + _applied_speed_delta
	_applied_speed_delta = 0.0
