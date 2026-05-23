class_name ExitZone
extends Area2D

# Bar-room exit zone (issue #181). An Area2D placed at each doorway in the
# bar room scene. When a Player body enters the area, emits player_entered;
# the parent BarRoom listens and re-emits its scene-level player_exited_bar
# so callers outside the bar don't have to know about the per-door wiring.
#
# Body filtering uses the "players" group tag (Player.gd adds this on
# _ready) so loose physics bodies or co-op remote kittens don't trip the
# zone.

signal player_entered()


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if not body.is_in_group("players"):
		return
	player_entered.emit()
