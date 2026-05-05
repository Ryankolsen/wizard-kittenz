class_name Player
extends CharacterBody2D

const ATTACK_COOLDOWN: float = 0.4

@export var speed: float = 60.0
@export var data: CharacterData

var _attack_controller: AttackController
var _hitbox: Area2D
var _spell_tree: SkillTree
var _power_ups: PowerUpManager
var _visual: Node2D
var _wobble_time: float = 0.0

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
	_power_ups = PowerUpManager.new()
	_visual = get_node_or_null("Placeholder")

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Re-read data.speed each frame so PowerUpManager mutations (Catnip)
	# propagate without needing a Player.gd hook.
	if data != null and data.speed > 0.0:
		speed = data.speed
	velocity = compute_velocity(input_dir, speed)
	# Track facing only when actually moving so a stationary kitten keeps its
	# last-known direction (relevant for backstab targeting).
	if input_dir != Vector2.ZERO:
		data.facing = input_dir.normalized()
	move_and_slide()
	_tick_spells(delta)
	_power_ups.tick(delta)
	_apply_ale_wobble(delta)
	if Input.is_action_just_pressed("attack"):
		_try_attack()
	if Input.is_action_just_pressed("cast_spell"):
		_try_cast_spell()

func collect_power_up(type_id: String) -> void:
	var effect := _power_ups.apply(type_id, data)
	if effect != null and effect is MushroomEffect:
		var mushroom: MushroomEffect = effect
		if not mushroom.random_spell_fired.is_connected(_on_mushroom_spell_fired):
			mushroom.random_spell_fired.connect(_on_mushroom_spell_fired)

# Mushroom power-up integration: every 2 seconds while active, cast the first
# ready unlocked spell against any enemies overlapping the swing-radius
# hitbox. No-op if no spells are unlocked yet — the buff is still "active",
# it just has nothing to fire.
func _on_mushroom_spell_fired() -> void:
	if _spell_tree == null or _hitbox == null:
		return
	var enemy_nodes := _overlapping_enemy_nodes()
	var enemy_data: Array = []
	for n in enemy_nodes:
		enemy_data.append(n.data)
	for spell in _spell_tree.get_unlocked_spells():
		if spell.cast():
			SpellEffectResolver.apply(spell, data, enemy_data)
			break

# Render-time sway while Ale is active. Visual-only; doesn't affect physics
# velocity or hitbox position. Resets to (0,0) when ale drops off.
func _apply_ale_wobble(delta: float) -> void:
	if _visual == null:
		return
	if _power_ups.is_active(PowerUpEffect.TYPE_ALE):
		_wobble_time += delta
		_visual.position = AleEffect.get_movement_offset(_wobble_time)
	elif _visual.position != Vector2.ZERO:
		_wobble_time = 0.0
		_visual.position = Vector2.ZERO

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
