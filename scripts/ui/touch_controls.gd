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
const TUTORIAL_TOPIC_MENU_SCENE := preload("res://scenes/tutorial_topic_menu.tscn")

@export var force_visible: bool = false

# Group the pause menu walks to hide these controls while it is open. The
# overlay lives on the same CanvasLayer.layer as the PauseMenu, so on touch
# platforms its QuickbarHUD slots (MOUSE_FILTER_PASS) would otherwise sit on
# top of the menu and swallow taps meant for the panel beneath it.
const PAUSE_HIDEABLE_GROUP := &"touch_controls"

func _ready() -> void:
	add_to_group(PAUSE_HIDEABLE_GROUP)
	# Tutorial target groups (issue #604, PRD #596): TutorialOverlay resolves
	# its "movement_attack" step targets via get_tree().get_first_node_in_group,
	# so the joystick and attack button register themselves directly here
	# rather than requiring hud.gd to hold a TouchControls reference.
	var joystick := get_node_or_null("Joystick") as Node
	if joystick != null:
		joystick.add_to_group("tutorial_target_joystick")
	var attack := get_node_or_null("AttackButton") as Node
	if attack != null:
		attack.add_to_group("tutorial_target_attack_button")
	# Issue #611 (PRD #596): TouchControls owns the visible HelpButton copy
	# on touch; HUD hides its own copy there (see hud.gd's _ready).
	var help_btn := get_node_or_null("HelpButton") as Button
	if help_btn != null:
		help_btn.pressed.connect(_on_help_pressed)
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
	var joystick := get_node_or_null("Joystick") as KittenJoystick
	if joystick != null:
		joystick.reset()

static func should_show(force: bool) -> bool:
	if force:
		return true
	return is_touch_platform()

static func is_touch_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android")

# Help-icon topic picker (issue #611, PRD #596). Same wiring shape as
# hud.gd's _on_help_pressed — each CanvasLayer gets its own TutorialTopicMenu
# instance since HUD's copy is desktop-visible and this copy is touch-visible.
func _on_help_pressed() -> void:
	var menu := TUTORIAL_TOPIC_MENU_SCENE.instantiate()
	add_child(menu)
	menu.topic_selected.connect(_on_help_topic_selected.bind(menu))
	menu.closed.connect(_on_help_menu_closed.bind(menu))

func _on_help_topic_selected(topic_id: String, menu: Node) -> void:
	TutorialSequencer.replay_topic(topic_id)
	menu.queue_free()

func _on_help_menu_closed(menu: Node) -> void:
	menu.queue_free()

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
	# Slice 4 of PRD #384 (#388): the potion belt is part of the cluster on
	# touch; mirror it alongside the quickbar so the column stays adjacent to
	# the magic grid on the opposite side. Optional — older scenes without a
	# PotionBeltHUD child still mirror the rest cleanly.
	var potion := get_node_or_null("PotionBeltHUD") as Control
	# Issue #611 (PRD #596): mirror the HelpButton alongside the rest of the
	# cluster. Optional — older scenes without a HelpButton child still
	# mirror the rest cleanly (same shape as the potion-belt optional guard).
	var help_btn := get_node_or_null("HelpButton") as Control
	var viewport_w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 480))
	if layout == ControlsSettings.LAYOUT_RIGHT_HAND:
		_mirror_x(joystick, viewport_w)
		_mirror_x(attack, viewport_w)
		_mirror_x(quickbar, viewport_w)
		if potion != null:
			_mirror_x(potion, viewport_w)
		if help_btn != null:
			_mirror_x(help_btn, viewport_w)

func _mirror_x(node: Control, viewport_w: float) -> void:
	var new_left := viewport_w - node.offset_right
	var new_right := viewport_w - node.offset_left
	node.offset_left = new_left
	node.offset_right = new_right
