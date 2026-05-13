class_name AudioSettingsManager
extends RefCounted

# Audio settings persistence + AudioServer wiring (PRD #42 / #49).
# Stores linear 0..1 volumes for BGM and SFX buses; converts to dB on
# apply via linear_to_db so a 0.0 slider maps to -80 dB (effectively
# muted) rather than the bus's configured floor.

const DEFAULT_PATH := "user://audio_settings.json"
const BGM_BUS := "BGM"
const SFX_BUS := "SFX"
const DEFAULT_BGM := 1.0
const DEFAULT_SFX := 1.0
const MUTE_FLOOR_DB := -80.0

static func set_bgm_volume(linear: float) -> void:
	_apply_bus_volume(BGM_BUS, linear)

static func set_sfx_volume(linear: float) -> void:
	_apply_bus_volume(SFX_BUS, linear)

# Returns the loaded settings dict (always populated with bgm/sfx keys
# so callers can index without a get() default). A missing file or
# malformed JSON falls back to the defaults — settings are non-critical,
# so silent fallback beats erroring out the player into the dungeon.
static func load_settings(path: String = DEFAULT_PATH) -> Dictionary:
	var result := {"bgm": DEFAULT_BGM, "sfx": DEFAULT_SFX}
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

static func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db := MUTE_FLOOR_DB if linear <= 0.0 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)
