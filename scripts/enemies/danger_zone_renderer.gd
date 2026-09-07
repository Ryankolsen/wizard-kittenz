class_name DangerZoneRenderer
extends Node2D

# Thin telegraph renderer (PRD #518 / tracer slice #533). It owns no shape data
# of its own: every point it fills and every colour it uses comes from the
# DangerZoneShape it was handed, which is the same instance damage resolution
# queries. That is the whole reason this node is so thin — two representations
# would drift, and the PRD's promise is that the drawn area is the hit area.
#
# Untested by design, matching the project's convention for node-side drawing
# (the geometry it draws is covered by test_danger_zone_shape.gd).

var zone: DangerZoneShape = null
# Drawn on the shape's own clock, supplied by the ability that owns it, so the
# flash-to-red frame is the frame the damage lands.
var _clock: Callable = Callable()
var _elapsed: float = 0.0


func configure(shape: DangerZoneShape, clock: Callable = Callable()) -> void:
	zone = shape
	_clock = clock
	# Zone coordinates are world-space (locked at telegraph start), so the
	# renderer must not inherit the enemy's transform as it walks or dashes.
	top_level = true
	global_position = Vector2.ZERO
	z_index = -1  # under the actors, like a decal on the floor


func _process(delta: float) -> void:
	if zone == null:
		queue_free()
		return
	_elapsed += delta
	if zone.is_expired(_time()):
		queue_free()
		return
	queue_redraw()


func _time() -> float:
	if _clock.is_valid():
		return float(_clock.call())
	return _elapsed


func _draw() -> void:
	if zone == null:
		return
	var t := _time()
	var corners := zone.outline()
	if corners.size() < 3:
		return
	var color := zone.color_at(t)
	draw_colored_polygon(corners, color)
	# Outline at full alpha so the boundary — the exact line containment tests
	# against — stays readable over any floor.
	var outline_color := Color(color.r, color.g, color.b, minf(1.0, color.a * 2.0))
	draw_polyline(corners + PackedVector2Array([corners[0]]), outline_color, 1.5)
