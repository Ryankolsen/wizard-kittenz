class_name Player
extends CharacterBody2D

const ATTACK_COOLDOWN: float = 0.4

@export var speed: float = 60.0
@export var data: CharacterData

var _attack_controller: AttackController
var _hitbox: Area2D

func _ready() -> void:
	if data == null:
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.current_character != null:
			data = gs.current_character
	if data == null:
		data = CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	_attack_controller = AttackController.new()
	_attack_controller.cooldown = ATTACK_COOLDOWN
	_hitbox = get_node_or_null("Hitbox")

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = compute_velocity(input_dir, speed)
	move_and_slide()
	if Input.is_action_just_pressed("attack"):
		_try_attack()

func _try_attack() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _attack_controller.try_attack(now):
		return
	if _hitbox == null:
		return
	for area in _hitbox.get_overlapping_areas():
		var node := area.get_parent()
		if node is Enemy and node.data != null:
			DamageResolver.apply(data, node.data)

static func compute_velocity(input_dir: Vector2, move_speed: float) -> Vector2:
	return input_dir * move_speed
