class_name BarRoom
extends Node2D

# Bar-room scene root (issue #181). Hosts the warm-tavern background, two
# ExitZone doorways the player walks through to return to the dungeon, and
# an enemy barrier that keeps pursuing enemies out of the safe room.
#
# Decisions:
# - player_exited_bar is the single scene-level exit signal — both
#   ExitZone children re-emit through this one signal so callers outside
#   the bar don't need to know about per-door wiring (user story 7: "exit
#   freely via either door").
# - The enemy barrier is a script-level guard layered on top of the
#   StaticBody2D doorway walls in the .tscn. Walls block the normal
#   move_and_slide path; the Area2D + _on_enemy_barrier_body_entered
#   pushback covers the contract that enemies do not cross even if a
#   per-kind behavior teleports them (e.g., Haunted Spray Bottle floats
#   over wall tiles by clearing collision_mask — see enemy.gd:60-63).
# - Enemies are pushed away from the bar's center along the entry vector.
#   The pushback distance is enough to drop them outside the trigger area
#   on the next physics step; tuned in QA (#184) if it feels off.

signal player_exited_bar()

const ENEMY_PUSHBACK_DISTANCE: float = 64.0


func _ready() -> void:
	for zone in get_exit_zones():
		if not zone.player_entered.is_connected(_on_exit_zone_player_entered):
			zone.player_entered.connect(_on_exit_zone_player_entered)
	var barrier := get_node_or_null("EnemyBarrier") as Area2D
	if barrier != null and not barrier.body_entered.is_connected(_on_enemy_barrier_body_entered):
		barrier.body_entered.connect(_on_enemy_barrier_body_entered)


# Returns the ExitZone children in the order they appear in the scene
# tree. Two zones are expected — one per visible doorway in
# bar_interior.png. Tests assert size == 2 to lock in the content
# contract; runtime wiring just iterates whatever zones exist.
func get_exit_zones() -> Array:
	var out: Array = []
	for child in get_children():
		if child is ExitZone:
			out.append(child)
	return out


func _on_exit_zone_player_entered() -> void:
	player_exited_bar.emit()


# Pushes an enemy body that crossed into the bar back outside along the
# vector from the bar's center to the body's current position. Non-enemy
# bodies (including the player) are ignored so the player can pass through
# the doorways freely.
func _on_enemy_barrier_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("enemies"):
		return
	if not (body is Node2D):
		return
	var b := body as Node2D
	var dir := (b.global_position - global_position)
	if dir.length_squared() <= 0.0:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	b.global_position += dir * ENEMY_PUSHBACK_DISTANCE
