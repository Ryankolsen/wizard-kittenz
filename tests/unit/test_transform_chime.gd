extends GutTest

# PRD #439 / issue #443 — procedural rising chime played at the flash beat of
# EvolveCongratsScreen's transformation sequence. Pure data (tone_sequence)
# is unit tested directly; play() is tested via the AudioStreamPlayer/
# AudioStreamGenerator node shape it builds, mirroring LevelUpEffect's
# _audio node setup.

func test_tone_sequence_returns_multiple_notes():
	var notes := TransformChime.tone_sequence()
	assert_true(notes.size() >= 2)

func test_tone_sequence_frequencies_ascend():
	var notes := TransformChime.tone_sequence()
	for i in range(1, notes.size()):
		assert_true(notes[i]["frequency"] >= notes[i - 1]["frequency"])

func test_tone_sequence_durations_are_positive():
	var notes := TransformChime.tone_sequence()
	for note in notes:
		assert_true(note["duration"] > 0.0)

func test_play_creates_audio_stream_player_with_generator_stream():
	var parent := Node.new()
	add_child_autofree(parent)
	TransformChime.play(parent)
	var player: AudioStreamPlayer = null
	for child in parent.get_children():
		if child is AudioStreamPlayer:
			player = child
	assert_not_null(player)
	assert_true(player.stream is AudioStreamGenerator)

func test_tone_sequence_is_deterministic():
	var a := TransformChime.tone_sequence()
	var b := TransformChime.tone_sequence()
	assert_eq(a, b)
