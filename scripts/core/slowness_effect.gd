class_name SlownessEffect
extends PowerUpEffect

# -50% move speed for `duration` seconds (issue #160). Stronger than Wet
# (-30%) and applies no visual tint — Player.gd handles tint separately for
# the wet variant. Same delta-tracking pattern as CatnipEffect.

const TYPE := "slowness"
const DEFAULT_DURATION := 3.0
const SPEED_PENALTY_PCT := 0.50

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
