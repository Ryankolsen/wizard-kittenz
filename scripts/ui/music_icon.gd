class_name MusicIcon
extends Control

# Vector-drawn speaker icon for the HUD mute button (issue: add a mute
# button). Drawn rather than loaded from a texture asset since no icon
# asset exists in the project yet — draw_* calls scale cleanly at any
# button size/resolution, which matters for mobile.

@export var muted: bool = false:
	set(value):
		muted = value
		queue_redraw()

const ICON_COLOR := Color(1, 1, 1, 1)
const LINE_WIDTH := 2.0

func _draw() -> void:
	var w := size.x
	var h := size.y
	var body_w := w * 0.25
	var body_h := h * 0.4
	var body_pos := Vector2(w * 0.08, h * 0.5 - body_h * 0.5)
	draw_rect(Rect2(body_pos, Vector2(body_w, body_h)), ICON_COLOR)
	var cone := PackedVector2Array([
		body_pos + Vector2(body_w, 0),
		body_pos + Vector2(body_w, body_h),
		Vector2(w * 0.55, h * 0.85),
		Vector2(w * 0.55, h * 0.15),
	])
	draw_colored_polygon(cone, ICON_COLOR)
	if muted:
		draw_line(Vector2(w * 0.62, h * 0.2), Vector2(w * 0.92, h * 0.8), ICON_COLOR, LINE_WIDTH)
		draw_line(Vector2(w * 0.92, h * 0.2), Vector2(w * 0.62, h * 0.8), ICON_COLOR, LINE_WIDTH)
	else:
		draw_arc(Vector2(w * 0.55, h * 0.5), w * 0.18, -PI / 3.0, PI / 3.0, 8, ICON_COLOR, LINE_WIDTH)
		draw_arc(Vector2(w * 0.55, h * 0.5), w * 0.3, -PI / 3.0, PI / 3.0, 8, ICON_COLOR, LINE_WIDTH)
