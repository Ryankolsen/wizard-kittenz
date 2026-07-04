extends Node

# Autoload owning the single looping background-music track for the whole
# application (PRD #397). Lives as an autoload so it survives scene
# transitions (change_scene_to_file / reload_current_scene): once started,
# the track plays for the rest of the session regardless of death/respawn,
# returning to character creation, or any other scene change.
#
# play_music() is the only entry point and is idempotent — main_scene.gd
# calls it from _ready() on every entry into gameplay (including scene
# reloads), and it only starts playback the first time.

const MUSIC_STREAM_PATH := "res://assets/music/wizard_music.mp3"
const BGM_BUS := "BGM"

var _player: AudioStreamPlayer = null

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.bus = BGM_BUS
	var stream := load(MUSIC_STREAM_PATH)
	if stream is AudioStreamMP3:
		stream.loop = true
	_player.stream = stream
	add_child(_player)

func play_music() -> void:
	if _player.playing:
		return
	_player.play()
