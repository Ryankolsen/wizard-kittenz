class_name TouchActionButton
extends Control

# A press-and-release touch button that forwards to Input.action_press /
# Input.action_release on a configured action_name. Mirrors keyboard
# behaviour so existing Input.is_action_just_pressed call sites work
# without modification.
#
# Touches are captured at _input level (not _gui_input) so a tap that
# starts inside the button but releases outside still fires the release.

@export var action_name: StringName = &""
@export var label_text: String = ""

var _active_touch_index: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_label()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_pressed(event)
		else:
			_handle_touch_released(event)

func _handle_touch_pressed(event: InputEventScreenTouch) -> void:
	if _active_touch_index != -1 or action_name == &"":
		return
	if not is_inside_rect(event.position, global_position, size):
		return
	_active_touch_index = event.index
	Input.action_press(action_name)
	queue_redraw()

func _handle_touch_released(event: InputEventScreenTouch) -> void:
	if event.index != _active_touch_index:
		return
	_active_touch_index = -1
	if action_name != &"":
		Input.action_release(action_name)
	queue_redraw()

func _draw() -> void:
	var pressed := _active_touch_index != -1
	var fill := Color(0.85, 0.25, 0.25, 0.85) if pressed else Color(0.18, 0.18, 0.22, 0.6)
	var border := Color(0.85, 0.85, 0.9, 0.85)
	draw_rect(Rect2(Vector2.ZERO, size), fill, true)
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.0)

func _update_label() -> void:
	var label := get_node_or_null("Label") as Label
	if label != null and label_text != "":
		label.text = label_text

# --- Static helpers ----------------------------------------------------

static func is_inside_rect(point: Vector2, origin: Vector2, sz: Vector2) -> bool:
	return point.x >= origin.x and point.x <= origin.x + sz.x \
		and point.y >= origin.y and point.y <= origin.y + sz.y
