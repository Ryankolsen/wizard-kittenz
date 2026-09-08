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
# Elapsed time is tracked locally per renderer instance rather than read off
# the ability that owns the zone. A fresh renderer is parented on every
# firing, but the ability has only one `_zone_elapsed` field that it resets
# to 0 the moment the *next* zone begins — so a renderer reading that field
# for its own (already-finished) zone would see elapsed jump back to 0 and
# read as freshly-started rather than expired, leaving the old zone visibly
# stuck on screen until the new cycle happened to reach the old zone's
# duration. Each renderer's own clock starts and ends with its own zone, so
# it can never be confused by a later firing resetting a field it doesn't
# share.
var _elapsed: float = 0.0


func configure(shape: DangerZoneShape) -> void:
	zone = shape
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
	if zone.is_expired(_elapsed):
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if zone == null:
		return
	var t := _elapsed
	# The ring's outline changes shape across the commit window (issue #573),
	# so it needs this renderer's own elapsed clock the same way color_at
	# already does below — lane/tether/disc ignore the argument.
	var corners := zone.outline(t)
	if corners.size() < 3:
		return
	var color := zone.color_at(t)
	draw_colored_polygon(corners, color)
	# Outline at full alpha so the boundary — the exact line containment tests
	# against — stays readable over any floor.
	var outline_color := Color(color.r, color.g, color.b, minf(1.0, color.a * 2.0))
	draw_polyline(corners + PackedVector2Array([corners[0]]), outline_color, 1.5)
