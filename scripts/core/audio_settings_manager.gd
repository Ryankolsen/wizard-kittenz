class_name AudioSettingsManager
extends RefCounted

# Audio settings persistence + AudioServer wiring (PRD #42 / #49).
# Stores linear 0..1 volumes for BGM and SFX buses; converts to dB on
# apply via linear_to_db so a 0.0 slider maps to -80 dB (effectively
# muted) rather than the bus's configured floor.

const DEFAULT_PATH := "user://audio_settings.json"
const BGM_BUS := "BGM"
const SFX_BUS := "SFX"
const DEFAULT_BGM := 0.5
const DEFAULT_SFX := 1.0
const DEFAULT_MUTED := false
const MUTE_FLOOR_DB := -80.0

static func set_bgm_volume(linear: float) -> void:
	_apply_bus_volume(BGM_BUS, linear)

static func set_sfx_volume(linear: float) -> void:
	_apply_bus_volume(SFX_BUS, linear)

# Soundtrack mute toggle (issue #620-ish "add a mute button"). Uses the
# BGM bus's mute flag rather than the volume-slider's -80dB floor so it's
# an independent on/off that doesn't clobber the player's saved BGM volume.
static func set_muted(muted: bool) -> void:
	var idx := AudioServer.get_bus_index(BGM_BUS)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, muted)

static func is_muted() -> bool:
	var idx := AudioServer.get_bus_index(BGM_BUS)
	if idx < 0:
		return DEFAULT_MUTED
	return AudioServer.is_bus_mute(idx)

# Returns the loaded settings dict (always populated with bgm/sfx/muted
# keys so callers can index without a get() default). A missing file or
# malformed JSON falls back to the defaults — settings are non-critical,
# so silent fallback beats erroring out the player into the dungeon.
static func load_settings(path: String = DEFAULT_PATH) -> Dictionary:
	var result := {"bgm": DEFAULT_BGM, "sfx": DEFAULT_SFX, "muted": DEFAULT_MUTED}
	if not FileAccess.file_exists(path):
		return result
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return result
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return result
	if parsed.has("bgm"):
		result["bgm"] = float(parsed["bgm"])
	if parsed.has("sfx"):
		result["sfx"] = float(parsed["sfx"])
	if parsed.has("muted"):
		result["muted"] = bool(parsed["muted"])
	return result

static func save_settings(data: Dictionary, path: String = DEFAULT_PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	f.close()
	return OK

# Applies the loaded settings to AudioServer. Used at app start to
# restore the last-saved volume without the player having to open the
# pause menu first.
static func apply_loaded(path: String = DEFAULT_PATH) -> void:
	var loaded := load_settings(path)
	set_bgm_volume(loaded["bgm"])
	set_sfx_volume(loaded["sfx"])
	set_muted(loaded["muted"])

static func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db := MUTE_FLOOR_DB if linear <= 0.0 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)
