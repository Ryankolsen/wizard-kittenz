class_name PowerUpPickup
extends Area2D

# World-entity wrapper for a power-up. Walking over the Area2D triggers
# pickup; Player applies the effect via its PowerUpManager and the pickup
# queue_frees itself. The visual placeholder color is set per type so the
# three power-ups read as distinct in the scene without needing real art.

@export var power_up_type: String = "catnip"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var visual: Polygon2D = get_node_or_null("Visual")
	if visual != null:
		visual.color = _color_for(power_up_type)

func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.collect_power_up(power_up_type)
		queue_free()

static func _color_for(t: String) -> Color:
	match t:
		PowerUpEffect.TYPE_CATNIP: return Color(0.4, 0.9, 0.4)
		PowerUpEffect.TYPE_ALE: return Color(0.9, 0.7, 0.3)
		PowerUpEffect.TYPE_MUSHROOMS: return Color(0.85, 0.4, 0.85)
	return Color(0.7, 0.7, 0.7)
