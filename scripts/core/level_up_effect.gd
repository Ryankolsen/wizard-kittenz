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

const VFX_DURATION: float = 0.6

# Returns true iff new_level strictly exceeds old_level. A multi-level
# jump counts as one true (callers fire one combined effect — the issue
# AC explicitly accepts either combined or per-level firing).
static func is_real_level_up(old_level: int, new_level: int) -> bool:
	return new_level > old_level

var _particles: CPUParticles2D
var _audio: AudioStreamPlayer

func _ready() -> void:
	_particles = get_node_or_null("Particles") as CPUParticles2D
	if _particles == null:
		_particles = CPUParticles2D.new()
		_particles.name = "Particles"
		_particles.amount = 24
		_particles.lifetime = VFX_DURATION
		_particles.one_shot = true
		_particles.emitting = false
		_particles.direction = Vector2(0, -1)
		_particles.spread = 180.0
		_particles.initial_velocity_min = 40.0
		_particles.initial_velocity_max = 80.0
		_particles.scale_amount_min = 1.5
		_particles.scale_amount_max = 3.0
		_particles.color = Color(1.0, 0.9, 0.3, 1.0)
		add_child(_particles)
	_audio = get_node_or_null("Audio") as AudioStreamPlayer
	if _audio == null:
		_audio = AudioStreamPlayer.new()
		_audio.name = "Audio"
		add_child(_audio)

func play(new_level: int = 0) -> void:
	if _particles != null:
		_particles.emitting = false
		_particles.restart()
		_particles.emitting = true
	if _audio != null and _audio.stream != null:
		_audio.play()
	triggered.emit(new_level)
