class_name ControlsSettingsManager
extends RefCounted

# Controls layout persistence (PRD #42 / #50). Stores the player's
# touch-control hand preference (joystick on the left vs. right) so it
# survives an app restart. Settings are non-critical, so a missing or
# malformed file silently falls back to the default — players don't
# get bounced out of the dungeon if their controls config gets nuked.

const DEFAULT_PATH := "user://controls_settings.json"
const LAYOUT_LEFT_HAND := "left_hand"
const LAYOUT_RIGHT_HAND := "right_hand"
const DEFAULT_LAYOUT := LAYOUT_LEFT_HAND
const VALID_LAYOUTS := [LAYOUT_LEFT_HAND, LAYOUT_RIGHT_HAND]

static func save_layout(layout: String, path: String = DEFAULT_PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"layout": layout}))
	f.close()
	return OK

static func load_layout(path: String = DEFAULT_PATH) -> String:
	if not FileAccess.file_exists(path):
		return DEFAULT_LAYOUT
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return DEFAULT_LAYOUT
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return DEFAULT_LAYOUT
	var layout := str(parsed.get("layout", DEFAULT_LAYOUT))
	if not VALID_LAYOUTS.has(layout):
		return DEFAULT_LAYOUT
	return layout
