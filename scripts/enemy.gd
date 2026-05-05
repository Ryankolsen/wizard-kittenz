class_name Enemy
extends CharacterBody2D

signal died

@export var data: EnemyData
@export var detection_radius: float = EnemyAIState.DETECTION_RADIUS
@export var melee_range: float = EnemyAIState.MELEE_RANGE
@export var move_speed: float = EnemyAIState.CHASE_SPEED

var state: int = EnemyAIState.State.IDLE
var _attack_controller: AttackController
var _player_ref: Player = null
var _died_emitted: bool = false

func _ready() -> void:
	add_to_group("enemies")
	if data == null:
		data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	_attack_controller = AttackController.new()
	_attack_controller.cooldown = EnemyAIState.ATTACK_COOLDOWN

func _physics_process(_delta: float) -> void:
	if data == null:
		return
	var player := _find_player()
	var distance := INF
	if player != null:
		distance = global_position.distance_to(player.global_position)
	apply_state_update(distance)
	match state:
		EnemyAIState.State.CHASE:
			_chase(player)
		EnemyAIState.State.ATTACK:
			velocity = Vector2.ZERO
			move_and_slide()
			_try_contact_damage(player)
		EnemyAIState.State.DEAD:
			velocity = Vector2.ZERO
			queue_free()
		_:
			velocity = Vector2.ZERO
			move_and_slide()

# Advances the AI state machine and emits `died` on the live -> DEAD edge.
# Public so tests can drive transitions without instantiating into a
# SceneTree; the runtime path is _physics_process calling this once per
# physics frame.
func apply_state_update(distance: float) -> void:
	if data == null:
		return
	state = EnemyAIState.next_state(state, distance, data.hp)
	if state == EnemyAIState.State.DEAD and not _died_emitted:
		_died_emitted = true
		died.emit()

func _chase(player: Player) -> void:
	if player == null:
		velocity = Vector2.ZERO
	else:
		var dir := (player.global_position - global_position).normalized()
		velocity = dir * move_speed
		if dir != Vector2.ZERO and data != null:
			data.facing = dir
	move_and_slide()

# Contact damage gated by AttackController so a melee-range enemy doesn't
# drain the player's HP every physics frame. Same cooldown shape as the
# player's swing — DamageResolver duck-types over both sides.
func _try_contact_damage(player: Player) -> void:
	if player == null or player.data == null or not player.data.is_alive():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _attack_controller.try_attack(now):
		return
	DamageResolver.apply(data, player.data)

func _find_player() -> Player:
	if _player_ref != null and is_instance_valid(_player_ref):
		return _player_ref
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.is_empty():
		return null
	var p := nodes[0]
	if p is Player:
		_player_ref = p
		return p
	return null
