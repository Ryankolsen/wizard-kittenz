class_name HealingBox
extends Node2D

const HP_PER_SEC: float = 2.0
const MP_PER_SEC: float = 1.0
const RADIUS: float = 40.0

var _hp_accum: float = 0.0
var _mp_accum: float = 0.0

func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/sprites/healing_box_sprite.png")
	add_child(sprite)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.8, 0.2, 0.12))

func _physics_process(_delta: float) -> void:
	var target = _find_overlapping_player()
	tick(_delta, target)

# Public so tests can drive healing without a SceneTree.
func tick(delta: float, target = null) -> void:
	if target == null or target.data == null:
		_hp_accum = 0.0
		_mp_accum = 0.0
		return

	_hp_accum += HP_PER_SEC * delta
	var hp_whole := int(_hp_accum)
	if hp_whole > 0:
		_hp_accum -= float(hp_whole)
		var healed: int = target.data.heal(hp_whole)
		if healed > 0 and is_inside_tree():
			FloatingText.spawn(target as Node, "+" + str(healed), Color(0.2, 1.0, 0.4))

	if target.data.max_mp <= 0:
		return
	_mp_accum += MP_PER_SEC * delta
	var mp_whole := int(_mp_accum)
	if mp_whole > 0:
		_mp_accum -= float(mp_whole)
		var mp_gap: int = target.data.max_mp - target.data.magic_points
		var mp_healed := mini(mp_whole, mp_gap)
		if mp_healed > 0:
			target.data.magic_points += mp_healed
			if is_inside_tree():
				FloatingText.spawn(target as Node, "+" + str(mp_healed) + " MP", Color(0.7, 0.4, 1.0))

func _find_overlapping_player():
	var tree := get_tree()
	if tree == null:
		return null
	var r2 := RADIUS * RADIUS
	for node in tree.get_nodes_in_group("player"):
		if node is Node2D and (node as Node2D).global_position.distance_squared_to(global_position) <= r2:
			return node
	return null
