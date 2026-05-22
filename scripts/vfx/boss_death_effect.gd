class_name BossDeathEffect
extends Node2D

# One-shot explosion + label spawned at the boss's world position on kill.
# Instantiate, set global_position, add to scene — it self-destructs.

const EXPLOSION_DURATION: float = 1.2
const LABEL_DURATION: float = 2.0

const EXPLOSION_COLORS: Array = [
	Color(1.0, 1.0, 1.0),  # white-hot core
	Color(1.0, 0.95, 0.3), # yellow
	Color(1.0, 0.45, 0.0), # orange
	Color(1.0, 0.05, 0.0), # deep red
]

func _ready() -> void:
	_spawn_explosion()
	_spawn_label()

func _spawn_explosion() -> void:
	for col: Color in EXPLOSION_COLORS:
		var p := CPUParticles2D.new()
		p.amount = 40
		p.lifetime = EXPLOSION_DURATION
		p.one_shot = true
		p.emitting = false
		p.direction = Vector2(0, -1)
		p.spread = 180.0
		p.initial_velocity_min = 250.0
		p.initial_velocity_max = 550.0
		p.gravity = Vector2(0, 60)
		p.scale_amount_min = 5.0
		p.scale_amount_max = 10.0
		p.color = col
		add_child(p)
		p.emitting = true

func _spawn_label() -> void:
	var lbl := Label.new()
	lbl.text = "BOSS DEFEATED!"
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.modulate = Color(1.0, 0.35, 0.05)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(320, 0)
	lbl.position = Vector2(-160, -60)
	add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", -220.0, LABEL_DURATION).from(-60.0)
	tw.tween_property(lbl, "modulate:a", 0.0, LABEL_DURATION * 0.6).from(1.0).set_delay(LABEL_DURATION * 0.4)
	tw.chain().tween_callback(queue_free)
