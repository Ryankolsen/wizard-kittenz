class_name Player
extends CharacterBody2D

const ATTACK_COOLDOWN: float = 0.4

@export var speed: float = 60.0
@export var data: CharacterData

var _attack_controller: AttackController
var _hitbox: Area2D
var _spell_tree: SkillTree

func _ready() -> void:
	if data == null:
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.current_character != null:
			data = gs.current_character
			_spell_tree = gs.skill_tree
	if data == null:
		data = CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	# data.speed is now the source of truth (per-class baseline). The @export
	# stays as an editor-time override for scene-only iteration.
	if data.speed > 0.0:
		speed = data.speed
	_attack_controller = AttackController.new()
	_attack_controller.cooldown = ATTACK_COOLDOWN
	_hitbox = get_node_or_null("Hitbox")

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = compute_velocity(input_dir, speed)
	# Track facing only when actually moving so a stationary kitten keeps its
	# last-known direction (relevant for backstab targeting).
	if input_dir != Vector2.ZERO:
		data.facing = input_dir.normalized()
	move_and_slide()
	_tick_spells(delta)
	if Input.is_action_just_pressed("attack"):
		_try_attack()
	if Input.is_action_just_pressed("cast_spell"):
		_try_cast_spell()

func _tick_spells(dt: float) -> void:
	if _spell_tree == null:
		return
	for spell in _spell_tree.get_unlocked_spells():
		spell.tick(dt)

func _try_attack() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _attack_controller.try_attack(now):
		return
	if _hitbox == null:
		return
	for area in _hitbox.get_overlapping_areas():
		var node := area.get_parent()
		if node is Enemy and node.data != null and node.data.is_alive():
			DamageResolver.apply(data, node.data)
			if not node.data.is_alive():
				ProgressionSystem.add_xp(data, node.data.xp_reward)
				SaveManager.save(data, SaveManager.DEFAULT_PATH, _spell_tree)
				node.queue_free()

# Cast the first ready unlocked spell. Same hitbox area as melee — keeps the
# "swing radius" model consistent across attack types until #11 introduces
# per-spell projectiles/areas.
func _try_cast_spell() -> void:
	if _spell_tree == null or _hitbox == null:
		return
	var enemy_nodes := _overlapping_enemy_nodes()
	var enemy_data: Array = []
	for n in enemy_nodes:
		enemy_data.append(n.data)
	for spell in _spell_tree.get_unlocked_spells():
		if not spell.cast():
			continue
		SpellEffectResolver.apply(spell, data, enemy_data)
		var awarded := false
		for n in enemy_nodes:
			if n.data != null and not n.data.is_alive():
				ProgressionSystem.add_xp(data, n.data.xp_reward)
				n.queue_free()
				awarded = true
		if awarded:
			SaveManager.save(data, SaveManager.DEFAULT_PATH, _spell_tree)
		return

func _overlapping_enemy_nodes() -> Array:
	var out: Array = []
	for area in _hitbox.get_overlapping_areas():
		var node := area.get_parent()
		if node is Enemy and node.data != null:
			out.append(node)
	return out

static func compute_velocity(input_dir: Vector2, move_speed: float) -> Vector2:
	return input_dir * move_speed
