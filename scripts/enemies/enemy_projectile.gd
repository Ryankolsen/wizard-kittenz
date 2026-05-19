class_name EnemyProjectile
extends Node2D

# Reusable linear projectile spawned by enemy behaviors (issue #159). Travels
# toward `target_position` at `speed` px/sec; fires `on_hit` on first contact
# with a node in the "player" group, then self-removes. Also self-removes
# after `max_range` px traveled so a missed shot doesn't stick around.
#
# Movement and despawn predicates are exposed as plain methods so tests can
# drive them without a SceneTree — same shape as EnemyBehavior (issue #157).

var target_position: Vector2 = Vector2.ZERO
var speed: float = 0.0
var radius: float = 8.0
var color: Color = Color(1.0, 1.0, 1.0, 1.0)
var max_range: float = 400.0
var on_hit: Callable = Callable()

var _travelled: float = 0.0
var _hit: bool = false
var _direction: Vector2 = Vector2.ZERO

func configure(p_target: Vector2, p_speed: float, p_radius: float,
		p_color: Color, p_max_range: float, p_on_hit: Callable) -> void:
	target_position = p_target
	speed = p_speed
	radius = p_radius
	color = p_color
	max_range = p_max_range
	on_hit = p_on_hit
	_direction = (target_position - position).normalized()

func _ready() -> void:
	# Aim from the spawn position toward the target if configure() was called
	# before the node was placed in the tree.
	if _direction == Vector2.ZERO:
		_direction = (target_position - position).normalized()
	queue_redraw()

func _physics_process(delta: float) -> void:
	simulate_move(delta)
	_check_player_overlap()
	if should_despawn():
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)

# Linear movement. Zero speed is a safe no-op (acceptance #5 / test 5).
func simulate_move(delta: float) -> void:
	if speed <= 0.0 or _direction == Vector2.ZERO:
		return
	var step := speed * delta
	position += _direction * step
	_travelled += step

# True after a hit (one-shot) or after exceeding max_range.
func should_despawn() -> bool:
	return _hit or _travelled >= max_range

# Fire the on_hit callback exactly once, then mark for despawn. Public so
# tests can drive the hit path without setting up an Area2D / SceneTree.
func _on_player_hit(player) -> void:
	if _hit:
		return
	_hit = true
	if on_hit.is_valid():
		on_hit.call(player)

func _check_player_overlap() -> void:
	if _hit:
		return
	var tree := get_tree()
	if tree == null:
		return
	var r2 := radius * radius
	for node in tree.get_nodes_in_group("player"):
		if node is Node2D and (node as Node2D).global_position.distance_squared_to(global_position) <= r2:
			_on_player_hit(node)
			return
