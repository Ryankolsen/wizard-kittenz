class_name ConfusionEffect
extends PowerUpEffect

# Reverses input direction for `duration` seconds (issue #160). The actual
# input flip happens in Player._physics_process by checking data.is_confused();
# this effect just maintains the counter on data so the rendering / movement
# code doesn't need to know about effect lifecycles.

const TYPE := "confusion"
const DEFAULT_DURATION := 3.0

func _init(duration_seconds: float = DEFAULT_DURATION) -> void:
	type = TYPE
	duration = duration_seconds
	remaining = duration_seconds

func _on_apply(target) -> void:
	target.push_confusion()

func _on_remove(target) -> void:
	target.pop_confusion()
