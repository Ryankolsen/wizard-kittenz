class_name Player
extends CharacterBody2D

@export var speed: float = 60.0
@export var data: CharacterData

func _ready() -> void:
	if data == null:
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.current_character != null:
			data = gs.current_character
	if data == null:
		data = CharacterData.make_new(CharacterData.CharacterClass.MAGE)

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = compute_velocity(input_dir, speed)
	move_and_slide()

static func compute_velocity(input_dir: Vector2, move_speed: float) -> Vector2:
	return input_dir * move_speed
