class_name TouchControls
extends CanvasLayer

# Mobile touch overlay: virtual joystick (left) + attack/cast buttons
# (right). Gated on platform — desktop runs are unaffected so dev/test
# screenshots stay clean. Tests can flip `force_visible` to render the
# controls in headless mode.

@export var force_visible: bool = false

func _ready() -> void:
	visible = should_show(force_visible)

static func should_show(force: bool) -> bool:
	if force:
		return true
	return is_touch_platform()

static func is_touch_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android")
