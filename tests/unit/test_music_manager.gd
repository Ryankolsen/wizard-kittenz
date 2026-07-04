extends GutTest

# MusicManager autoload (PRD #397 / issue #399). Tolerates the BGM bus
# being absent in the isolated test environment, consistent with the
# convention in test_audio_settings_manager.gd.

func _music_player() -> AudioStreamPlayer:
	var manager := get_node_or_null("/root/MusicManager")
	assert_not_null(manager, "MusicManager autoload must be registered")
	return manager.find_child("MusicPlayer", false, false) as AudioStreamPlayer

func test_play_music_starts_playback():
	var manager := get_node_or_null("/root/MusicManager")
	assert_not_null(manager, "MusicManager autoload must be registered")
	manager.play_music()
	var player := _music_player()
	assert_true(player.playing, "play_music() must start playback")

func test_music_stream_is_wizard_music_and_loops():
	var player := _music_player()
	assert_not_null(player.stream, "MusicPlayer must have a stream assigned")
	assert_eq(player.stream.resource_path, "res://assets/music/wizard_music.mp3",
		"MusicPlayer stream must be wizard_music.mp3")
	assert_true(player.stream.loop, "wizard_music.mp3 stream must loop")

func test_music_player_routed_to_bgm_bus():
	var player := _music_player()
	assert_eq(player.bus, "BGM", "MusicPlayer must be routed to the BGM bus")

func test_play_music_is_idempotent_when_already_playing():
	var manager := get_node_or_null("/root/MusicManager")
	assert_not_null(manager, "MusicManager autoload must be registered")
	manager.play_music()
	var player := _music_player()
	assert_true(player.playing, "playback must be active after first play_music()")
	await get_tree().create_timer(0.2).timeout
	var position_before := player.get_playback_position()
	manager.play_music()
	assert_true(player.playing, "playback must remain active after redundant play_music()")
	assert_gt(position_before, 0.0, "playback position must have advanced before the redundant call")
	assert_almost_eq(player.get_playback_position(), position_before, 0.05,
		"redundant play_music() must not restart playback position")

func test_music_manager_is_autoload_and_survives_scene_reload():
	# Calling get_tree().reload_current_scene() here would clobber the GUT
	# runner's own scene (see main_scene.gd's _finalize_and_reload comment
	# for the same caveat), so this simulates a scene transition by
	# instantiating and freeing a throwaway scene node instead — MusicManager
	# lives under /root as an autoload, a sibling of (not a child of) the
	# current scene, so it must be unaffected either way.
	var manager := get_node_or_null("/root/MusicManager")
	assert_not_null(manager, "MusicManager autoload must exist before scene transition")
	manager.play_music()
	var player := _music_player()
	assert_true(player.playing, "playback must be active before scene transition")

	var throwaway := Node.new()
	add_child_autofree(throwaway)
	throwaway.free()
	await get_tree().process_frame

	assert_not_null(get_node_or_null("/root/MusicManager"),
		"MusicManager autoload must still exist after a scene transition")
	assert_true(player.playing,
		"playback must continue uninterrupted through a scene transition")
