class_name SlashEffect
extends Node2D

const DURATION: float = 0.14

static func spawn(target: Node2D, attack_dir: Vector2) -> void:
	if target == null or not is_instance_valid(target):
		return
	var parent := target.get_parent()
	if parent == null:
		return
	var effect := SlashEffect.new()
	parent.add_child(effect)
	effect.global_position = target.global_position
	effect._play(attack_dir)

func _play(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var size := 10.0
	var curve := 5.0

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(1.0, 1.0, 0.8, 1.0)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	# 5-point arc perpendicular to attack dir, bowing forward
	for i in 5:
		var t: float = (float(i) / 4.0) * 2.0 - 1.0
		line.add_point(perp * size * t + dir * curve * (1.0 - t * t))
	add_child(line)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, DURATION)
	tween.tween_callback(queue_free)
