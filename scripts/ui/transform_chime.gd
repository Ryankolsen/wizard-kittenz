class_name TransformChime
extends RefCounted

# PRD #439 / issue #443 — short rising-tone chime synthesized at runtime via
# AudioStreamGenerator, played once at the flash beat of
# EvolveCongratsScreen._play_transformation(). No audio asset files; a
# swappable seam so a real SFX asset can replace this later. Same structural
# pattern as LevelUpEffect's _audio node setup.

const _MIX_RATE := 44100.0

# Ordered rising three-note chime. Static data (no randomness) so playback
# stays deterministic and testable.
static func tone_sequence() -> Array:
	return [
		{"frequency": 523.25, "duration": 0.1},  # C5
		{"frequency": 659.25, "duration": 0.1},  # E5
		{"frequency": 783.99, "duration": 0.15}, # G5
	]

static func play(parent: Node) -> void:
	var player := AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _MIX_RATE
	player.stream = generator
	parent.add_child(player)
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if playback == null:
		return
	for note in tone_sequence():
		_fill_tone(playback, note["frequency"], note["duration"])

static func _fill_tone(playback: AudioStreamGeneratorPlayback, frequency: float, duration: float) -> void:
	var frame_count := int(_MIX_RATE * duration)
	var phase := 0.0
	var increment := frequency / _MIX_RATE
	for i in range(frame_count):
		var sample := sin(phase * TAU)
		playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + increment, 1.0)
