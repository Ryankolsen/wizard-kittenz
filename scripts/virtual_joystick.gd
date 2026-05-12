class_name VirtualJoystick
extends Control

# Analog touch joystick that drives the move_left/right/up/down InputMap
# actions via Input.action_press(strength). Listens at _input level so a
# drag that leaves the joystick's rect keeps tracking — the captured
# touch index is the source of truth, not which Control the touch is
# currently over.
#
# The four pieces of math (clamp, deadzone, normalize, per-action
# strength) are exposed as static helpers so they can be exercised by
# GUT without booting a SceneTree or stubbing Input.

const DEFAULT_BASE_RADIUS := 28.0
const DEFAULT_DEADZONE_FRACTION := 0.2
# Forgiving capture target: a touch within 1.5x the base radius still
# counts as "on the joystick". Without this, thumb taps that land just
# past the visual ring feel unresponsive.
const CAPTURE_RADIUS_MULTIPLIER := 1.5

const MOVE_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
]

@export var base_radius: float = DEFAULT_BASE_RADIUS
@export var deadzone_fraction: float = DEFAULT_DEADZONE_FRACTION

var _active_touch_index: int = -1
var _thumb_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# We capture touches via _input so a drag past the rect still tracks;
	# the Control rect is purely a draw anchor.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_pressed(event)
		else:
			_handle_touch_released(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)

func _handle_touch_pressed(event: InputEventScreenTouch) -> void:
	if _active_touch_index != -1:
		return
	var center := _base_center()
	if event.position.distance_to(center) > base_radius * CAPTURE_RADIUS_MULTIPLIER:
		return
	_active_touch_index = event.index
	_update_offset(event.position)

func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_touch_index:
		return
	_update_offset(event.position)

func _handle_touch_released(event: InputEventScreenTouch) -> void:
	if event.index != _active_touch_index:
		return
	_active_touch_index = -1
	_thumb_offset = Vector2.ZERO
	_release_all_move_actions()
	queue_redraw()

func _update_offset(touch_pos: Vector2) -> void:
	_thumb_offset = compute_clamped_offset(touch_pos, _base_center(), base_radius)
	var direction := compute_direction(_thumb_offset, base_radius, deadzone_fraction)
	_apply_direction(direction)
	queue_redraw()

func _apply_direction(direction: Vector2) -> void:
	var strengths := compute_action_strengths(direction)
	for action in MOVE_ACTIONS:
		var strength: float = strengths.get(String(action), 0.0)
		if strength > 0.0:
			Input.action_press(action, strength)
		else:
			Input.action_release(action)

func _release_all_move_actions() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)

func _base_center() -> Vector2:
	return global_position + size * 0.5

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, base_radius, Color(0.08, 0.08, 0.12, 0.55))
	draw_arc(center, base_radius, 0.0, TAU, 32, Color(0.85, 0.85, 0.9, 0.7), 1.0)
	draw_circle(center + _thumb_offset, base_radius * 0.45, Color(0.85, 0.85, 0.9, 0.85))

# --- Static helpers (testable without Input/SceneTree) ------------------

static func compute_clamped_offset(touch_pos: Vector2, center: Vector2, max_radius: float) -> Vector2:
	var offset := touch_pos - center
	var length := offset.length()
	if length > max_radius and length > 0.0:
		offset = offset / length * max_radius
	return offset

static func compute_direction(offset: Vector2, max_radius: float, deadzone_fraction_arg: float) -> Vector2:
	if max_radius <= 0.0:
		return Vector2.ZERO
	var deadzone := max_radius * deadzone_fraction_arg
	var length := offset.length()
	if length <= deadzone:
		return Vector2.ZERO
	return offset / max_radius

static func compute_action_strengths(direction: Vector2) -> Dictionary:
	return {
		"move_left": maxf(-direction.x, 0.0),
		"move_right": maxf(direction.x, 0.0),
		"move_up": maxf(-direction.y, 0.0),
		"move_down": maxf(direction.y, 0.0),
	}
