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

# Group the pause menu walks to hide these controls while it is open. The
# overlay lives on the same CanvasLayer.layer as the PauseMenu, so on touch
# platforms its QuickbarHUD slots (MOUSE_FILTER_PASS) would otherwise sit on
# top of the menu and swallow taps meant for the panel beneath it.
const PAUSE_HIDEABLE_GROUP := &"touch_controls"

func _ready() -> void:
	add_to_group(PAUSE_HIDEABLE_GROUP)
	visible = should_show(force_visible)
	apply_layout(ControlsSettings.load_layout())

# Called by the PauseMenu when it opens/closes. While the menu is open the
# overlay hides entirely; on close it returns to its platform-gated default
# rather than blindly showing (so desktop stays clean).
func set_menu_open(menu_open: bool) -> void:
	visible = false if menu_open else should_show(force_visible)

# Clears the virtual joystick's captured touch and held direction. Used on
# scene-context changes (bar entry) so a finger still resting on the stick
# from walking onto the entrance doesn't keep driving movement in the new
# context. No-op if the joystick node is absent (headless test scenes).
func reset_joystick() -> void:
	var joystick := get_node_or_null("Joystick") as VirtualJoystick
	if joystick != null:
		joystick.reset()

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
