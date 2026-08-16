class_name Hooman
extends CharacterBody2D

# Rented companion node (PRD #491, issue #496). Spawn/follow/lifecycle only —
# CHASE/ATTACK/HEAL are reachable states (driven by HoomanAIState, #493) but
# are no-ops at the node level until #497 (HP/aggro) and #498 (combat/heal)
# land.
#
# Movement is plain position math (not move_and_slide) since the hooman is a
# non-colliding companion that drifts/snaps toward the player rather than
# navigating obstacles — this also keeps tick() callable headless (no
# SceneTree / physics server required), matching Enemy.apply_state_update's
# testable-without-scene-tree shape.

const RIGHT_TEXTURE_PATH := "res://assets/sprites/hooman_right.png"

# Follow tuning. Comfort radius is the "stand near the player" band; beyond
# LEASH_DISTANCE the hooman snaps back in rather than visibly catching up —
# covers cases like a floor transition teleport or the player sprinting
# through a doorway.
const COMFORT_RADIUS: float = 40.0
const LEASH_DISTANCE: float = 220.0
const FOLLOW_SPEED: float = 140.0

var state: int = HoomanAIState.State.FOLLOW
var _active: bool = false


func _ready() -> void:
	add_to_group("hooman")
	if get_node_or_null("Sprite2D") == null:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		if ResourceLoader.exists(RIGHT_TEXTURE_PATH):
			sprite.texture = load(RIGHT_TEXTURE_PATH)
		add_child(sprite)
	if get_node_or_null("CollisionShape2D") == null:
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = 16.0
		shape.shape = circle
		add_child(shape)


# Pure/headless-callable per-frame driver, same shape as
# Enemy.apply_state_update. Advances the AI state machine from
# HoomanAIState.next_state, then — for this slice — applies follow movement
# only in FOLLOW; CHASE/ATTACK/HEAL are no-ops at the node level until
# #497/#498 wire up combat and healing.
func tick(delta: float, player_pos: Vector2, nearest_mob_dist: float, player_hp_percent: float, is_active: bool) -> void:
	_active = is_active
	state = HoomanAIState.next_state(state, nearest_mob_dist, player_hp_percent, is_active)
	if state == HoomanAIState.State.FOLLOW:
		_apply_follow(delta, player_pos)


# Pure helper: velocity that would carry `pos` toward `player_pos` at
# `speed`. Zero when already at the player's position.
static func follow_velocity(pos: Vector2, player_pos: Vector2, speed: float = FOLLOW_SPEED) -> Vector2:
	var to_player := player_pos - pos
	if to_player.length_squared() <= 0.0:
		return Vector2.ZERO
	return to_player.normalized() * speed


# Drifts toward the player once outside COMFORT_RADIUS, snapping to just
# outside the comfort band when separation exceeds LEASH_DISTANCE (catch-up
# after a teleport, e.g. floor transition or bar exit) rather than visibly
# racing to close the gap.
func _apply_follow(delta: float, player_pos: Vector2) -> void:
	var to_player := player_pos - global_position
	var dist := to_player.length()
	if dist <= COMFORT_RADIUS:
		velocity = Vector2.ZERO
		return
	var dir := to_player / dist
	if dist > LEASH_DISTANCE:
		global_position = player_pos - dir * COMFORT_RADIUS
		velocity = Vector2.ZERO
		return
	velocity = dir * FOLLOW_SPEED
	global_position += velocity * delta
	_update_facing(dir)


func _update_facing(dir: Vector2) -> void:
	if dir.x == 0.0:
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.flip_h = dir.x < 0.0
