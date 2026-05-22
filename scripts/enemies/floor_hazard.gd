class_name FloorHazard
extends Node2D

# Reusable timed floor zone (issue #158). Renders a colored disc, optionally
# applies a slow + damage-per-sec to any player overlapping it, and removes
# itself after `duration` seconds.
#
# Spawners (Angry Pigeon drop / Rogue Roomba trail in #161, #162) instantiate,
# `configure(...)`, then add to the scene. Slow magnitude and damage rate are
# independent so the same node serves a pure slow puddle (damage_per_sec = 0)
# or a pure damage strip (slow_percent = 0).
#
# `tick` / `apply_to` / `remove_from` are public so tests can drive the
# timer / slow / damage paths without a SceneTree — same shape as
# EnemyProjectile (issue #159).

var duration: float = 1.0
var slow_percent: float = 0.0
var damage_per_sec: float = 0.0
var radius: float = 32.0
var color: Color = Color(0.5, 0.5, 0.5, 0.4)

var elapsed: float = 0.0

# Fractional damage carries across ticks so `damage_per_sec * delta < 1` still
# eventually deals damage. take_damage takes ints so we accumulate then floor.
var _damage_accum: float = 0.0

# Per-target slow bookkeeping. Tracking the applied delta (vs. recomputing as a
# percentage on remove) means concurrent slows from other sources don't double-
# subtract when this hazard expires — mirrors SlownessEffect's delta-tracking.
var _slowed_target = null
var _applied_slow_delta: float = 0.0

func configure(p_duration: float, p_slow_percent: float,
		p_damage_per_sec: float, p_radius: float, p_color: Color) -> void:
	duration = p_duration
	slow_percent = p_slow_percent
	damage_per_sec = p_damage_per_sec
	radius = p_radius
	color = p_color

func _ready() -> void:
	z_index = -1
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)

func _physics_process(delta: float) -> void:
	var target = _find_overlapping_player()
	if target != null and _slowed_target == null:
		apply_to(target)
	elif target == null and _slowed_target != null:
		remove_from(_slowed_target)
	tick(delta, target)
	if is_expired():
		if _slowed_target != null:
			remove_from(_slowed_target)
		queue_free()

# Advance the lifetime timer and (if a target is in-zone) accrue damage.
# Public so tests can drive without a SceneTree.
func tick(delta: float, target = null) -> void:
	elapsed += delta
	if target == null or damage_per_sec <= 0.0:
		return
	_damage_accum += damage_per_sec * delta
	var whole := int(_damage_accum)
	if whole <= 0:
		return
	_damage_accum -= float(whole)
	if target.has_method("take_damage"):
		target.take_damage(whole)

func is_expired() -> bool:
	return elapsed >= duration

# Apply the slow to `target`, capturing the delta so remove_from restores
# exactly what was subtracted regardless of intervening speed mutations.
func apply_to(target) -> void:
	if target == null or _slowed_target != null or slow_percent <= 0.0:
		return
	_applied_slow_delta = float(target.speed) * slow_percent
	target.speed = float(target.speed) - _applied_slow_delta
	_slowed_target = target

func remove_from(target) -> void:
	if _slowed_target == null or target != _slowed_target:
		return
	target.speed = float(target.speed) + _applied_slow_delta
	_applied_slow_delta = 0.0
	_slowed_target = null

func _find_overlapping_player():
	var tree := get_tree()
	if tree == null:
		return null
	var r2 := radius * radius
	for node in tree.get_nodes_in_group("player"):
		if node is Node2D and (node as Node2D).global_position.distance_squared_to(global_position) <= r2:
			return node
	return null
