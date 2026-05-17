class_name LevelUpEffect
extends Node2D

# Visual + audio celebration that fires when a player gains a level.
# Lives as a child of Player so the burst follows the character. The
# trigger source is the scene layer: solo callers level-diff the local
# CharacterData around ProgressionSystem.add_xp; co-op callers connect
# to CoopXPSubscriber.level_up on the active session's subscriber.
#
# Pure predicate (is_real_level_up) extracted as a static so the "should
# fire" rule is unit-testable without booting a scene. Same shape as
# StatBadge.should_show.

signal triggered(new_level: int)

const VFX_DURATION: float = 0.8
const LABEL_DURATION: float = 1.2
const RING_DURATION: float = 0.5

const CONFETTI_COLORS: Array = [
	Color(1.0, 0.85, 0.1),  # gold
	Color(1.0, 0.2,  0.8),  # magenta
	Color(0.1, 0.9,  1.0),  # cyan
	Color(0.3, 1.0,  0.3),  # lime green
]

# Returns true iff new_level strictly exceeds old_level. A multi-level
# jump counts as one true (callers fire one combined effect — the issue
# AC explicitly accepts either combined or per-level firing).
static func is_real_level_up(old_level: int, new_level: int) -> bool:
	return new_level > old_level

var _confetti: Array = []
var _audio: AudioStreamPlayer

func _ready() -> void:
	for col in CONFETTI_COLORS:
		var p := CPUParticles2D.new()
		p.amount = 16
		p.lifetime = VFX_DURATION
		p.one_shot = true
		p.emitting = false
		p.direction = Vector2(0, -1)
		p.spread = 180.0
		p.initial_velocity_min = 150.0
		p.initial_velocity_max = 300.0
		p.gravity = Vector2(0, 500)
		p.scale_amount_min = 2.5
		p.scale_amount_max = 5.0
		p.color = col
		add_child(p)
		_confetti.append(p)

	_audio = get_node_or_null("Audio") as AudioStreamPlayer
	if _audio == null:
		_audio = AudioStreamPlayer.new()
		_audio.name = "Audio"
		add_child(_audio)

func _spawn_ring() -> void:
	if not is_inside_tree():
		return
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	var steps := 32
	for i in range(steps + 1):
		var angle := (float(i) / steps) * TAU
		pts.append(Vector2(cos(angle), sin(angle)) * 12.0)
	ring.points = pts
	ring.width = 4.0
	ring.default_color = Color.WHITE
	add_child(ring)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(6.0, 6.0), RING_DURATION).from(Vector2(0.5, 0.5))
	tw.tween_property(ring, "modulate:a", 0.0, RING_DURATION).from(1.0)
	tw.chain().tween_callback(ring.queue_free)

func _spawn_label(new_level: int) -> void:
	if not is_inside_tree():
		return
	var lbl := Label.new()
	lbl.text = "LEVEL UP!" if new_level <= 0 else "LEVEL %d!" % new_level
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.modulate = Color(1.0, 0.9, 0.1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(100, 0)
	lbl.position = Vector2(-50, -50)
	add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", -130.0, LABEL_DURATION).from(-50.0)
	tw.tween_property(lbl, "modulate:a", 0.0, LABEL_DURATION).from(1.0)
	tw.chain().tween_callback(lbl.queue_free)

func play(new_level: int = 0) -> void:
	for p: CPUParticles2D in _confetti:
		if p != null:
			p.emitting = false
			p.restart()
			p.emitting = true
	_spawn_ring()
	_spawn_label(new_level)
	if _audio != null and _audio.stream != null:
		_audio.play()
	triggered.emit(new_level)
