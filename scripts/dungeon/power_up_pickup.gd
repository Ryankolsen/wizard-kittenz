class_name PowerUpPickup
extends Area2D

# World-entity wrapper for a power-up. Walking over the Area2D triggers
# pickup; Player applies the effect via its PowerUpManager and the pickup
# queue_frees itself. The Sprite2D texture is set per type at runtime.

@export var power_up_type: String = "catnip"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var visual: Sprite2D = get_node_or_null("Visual")
	if visual != null:
		visual.texture = _texture_for(power_up_type)
		visual.scale = Vector2(0.5, 0.5)

func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.collect_power_up(power_up_type)
		# Issue #468: ale pickups feed the same shared `drinks` counter as
		# the bartender's beer purchase, so both sources count toward the
		# tiered Happy Hour/Bar Regular/Liver of Steel achievements. Other
		# power-up types (catnip, mushrooms) never touch this counter.
		if power_up_type == PowerUpEffect.TYPE_ALE:
			var gs := get_node_or_null("/root/GameState")
			if gs != null:
				gs.achievement_service.increment_counter("drinks", 1)
		# Issue #469: catnip pickups feed the `catnip_snarfed` counter for the
		# tiered Sniff Test/Catnip Enthusiast/Certified Space Cat achievements.
		# Other power-up types (ale, mushrooms) never touch this counter.
		if power_up_type == PowerUpEffect.TYPE_CATNIP:
			var gs2 := get_node_or_null("/root/GameState")
			if gs2 != null:
				gs2.achievement_service.increment_counter("catnip_snarfed", 1)
		queue_free()

static func _texture_for(t: String) -> Texture2D:
	match t:
		PowerUpEffect.TYPE_CATNIP: return load("res://assets/sprites/catnip_sprite.png")
		PowerUpEffect.TYPE_ALE: return load("res://assets/sprites/ale_sprite.png")
		PowerUpEffect.TYPE_MUSHROOMS: return load("res://assets/sprites/mushroom_sprite.png")
	return null

