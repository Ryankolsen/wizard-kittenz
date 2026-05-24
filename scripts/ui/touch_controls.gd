class_name TouchControls
extends CanvasLayer

# Mobile touch overlay: virtual joystick + attack/cast buttons. Gated on
# platform — desktop runs are unaffected so dev/test screenshots stay
# clean. Tests can flip `force_visible` to render the controls in
# headless mode.
#
# Layout (PRD #42 / #50) reads from ControlsSettingsManager at _ready
# and swaps the joystick and action buttons across the screen. The
# .tscn ships the left-hand layout (joystick on the left); right-hand
# mirrors the two clusters around the viewport's horizontal center.

const ControlsSettings := preload("res://scripts/core/controls_settings_manager.gd")

@export var force_visible: bool = false

func _ready() -> void:
	visible = should_show(force_visible)
	apply_layout(ControlsSettings.load_layout())

static func should_show(force: bool) -> bool:
	if force:
		return true
	return is_touch_platform()

static func is_touch_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android")

# Mirrors the joystick / action-button clusters when the player picks
# the right-hand layout. The .tscn ships the left-hand offsets, so the
# swap is computed against the viewport width — keeps the spacing
# consistent if the project's display size changes later.
func apply_layout(layout: String) -> void:
	var joystick := get_node_or_null("Joystick") as Control
	var attack := get_node_or_null("AttackButton") as Control
	# Slice 3 of PRD #210: the single CastButton was replaced with a 2×2
	# QuickbarHUD. The mirroring still operates per-cluster so the four-slot
	# grid pivots as one node across the viewport's horizontal center.
	var quickbar := get_node_or_null("QuickbarHUD") as Control
	if joystick == null or attack == null or quickbar == null:
		return
	var viewport_w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 480))
	if layout == ControlsSettings.LAYOUT_RIGHT_HAND:
		_mirror_x(joystick, viewport_w)
		_mirror_x(attack, viewport_w)
		_mirror_x(quickbar, viewport_w)

func _mirror_x(node: Control, viewport_w: float) -> void:
	var new_left := viewport_w - node.offset_right
	var new_right := viewport_w - node.offset_left
	node.offset_left = new_left
	node.offset_right = new_right
