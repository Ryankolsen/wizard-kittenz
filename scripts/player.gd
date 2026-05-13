class_name Player
extends CharacterBody2D

signal died

const ATTACK_COOLDOWN: float = 0.4

@export var speed: float = 60.0
@export var data: CharacterData

var _attack_controller: AttackController
var _hitbox: Area2D
var _spell_tree: SkillTree
var _power_ups: PowerUpManager
var _visual: Node2D
var _wobble_time: float = 0.0
var _died_emitted: bool = false
var _level_up_effect: LevelUpEffect
var _coop_level_up_bound: bool = false

func _ready() -> void:
	add_to_group("player")
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
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = load("res://assets/sprites/wizard_kitten.png")
	_visual = sprite
	_level_up_effect = get_node_or_null("LevelUpEffect") as LevelUpEffect
	_bind_coop_level_up()

func _physics_process(delta: float) -> void:
	if data != null and not data.is_alive():
		_check_died()
		velocity = Vector2.ZERO
		move_and_slide()
		return
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
	_maybe_broadcast_position()
	if Input.is_action_just_pressed("attack"):
		_try_attack()
	if Input.is_action_just_pressed("cast_spell"):
		_try_cast_spell()

# Emit `died` exactly once when hp first reaches zero. The death-screen
# revive button calls LocalReviveRouter.revive, which sets hp back above
# zero — _died_emitted resets nowhere, but a successful revive simply
# means data.is_alive() goes true again so this branch is skipped.
func _check_died() -> void:
	if _died_emitted:
		return
	_died_emitted = true
	died.emit()

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
	_play_attack_flash()
	if _hitbox == null:
		return
	for area in _hitbox.get_overlapping_areas():
		var node := area.get_parent()
		if node is Enemy and node.data != null and node.data.is_alive():
			DamageResolver.apply(data, node.data)
			if not node.data.is_alive():
				_award_kill_xp(node.data)
				_record_meta_progress()
				SaveManager.save(data, SaveManager.DEFAULT_PATH, _spell_tree, _meta_tracker(), _offline_xp_tracker(), _cosmetic_inventory(), _paid_unlocks())
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
				_award_kill_xp(n.data)
				n.queue_free()
				awarded = true
		if awarded:
			_record_meta_progress()
			SaveManager.save(data, SaveManager.DEFAULT_PATH, _spell_tree, _meta_tracker(), _offline_xp_tracker(), _cosmetic_inventory(), _paid_unlocks())
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

# Updates the autoload tracker with the player's current class+level so the
# UnlockRegistry can react to "reach level N with class X" gates. Safe to
# call frequently — record_level_reached takes a max, not a sum.
func _record_meta_progress() -> void:
	var tracker := _meta_tracker()
	if tracker == null or data == null:
		return
	tracker.record_level_reached(
		CharacterFactory.name_from_class(data.character_class), data.level)

func _meta_tracker() -> MetaProgressionTracker:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.meta_tracker

# Routes a local kill to the right reward path: solo applies XP locally
# and tallies into the offline counter; co-op broadcasts XP via the
# active session. The branch itself lives in KillRewardRouter so it can
# be tested without booting a Player scene. Null enemy_data degrades to
# a no-op (defensive for a future kill source that doesn't pass the
# data, e.g. DoT spells).
func _award_kill_xp(enemy_data: EnemyData) -> void:
	if data == null or enemy_data == null:
		return
	# Solo: route_kill mutates data.level via ProgressionSystem.add_xp, so
	# a before/after diff is the level-up edge. Co-op: route_kill broadcasts
	# via xp_broadcaster; data.level on the Player is untouched and the
	# level-up edge arrives via LocalXPRouter.level_up (wired in _ready).
	var old_level := data.level
	KillRewardRouter.route_kill(
		data,
		enemy_data,
		_coop_session(),
		_local_player_id(),
		_offline_xp_tracker(),
		_lobby()
	)
	if LevelUpEffect.is_real_level_up(old_level, data.level):
		_trigger_level_up_effect(data.level)
	# Co-op router may have been built after _ready (session.start() runs
	# after the player spawns). Re-attempt binding here so the first kill
	# that triggers a session-start path still picks up subsequent level
	# events.
	if not _coop_level_up_bound:
		_bind_coop_level_up()

func _bind_coop_level_up() -> void:
	if _coop_level_up_bound:
		return
	var session := _coop_session()
	if session == null or session.xp_router == null:
		return
	if not session.xp_router.level_up.is_connected(_on_coop_level_up):
		session.xp_router.level_up.connect(_on_coop_level_up)
	_coop_level_up_bound = true

func _on_coop_level_up(old_level: int, new_level: int) -> void:
	if LevelUpEffect.is_real_level_up(old_level, new_level):
		_trigger_level_up_effect(new_level)

func _trigger_level_up_effect(new_level: int) -> void:
	if _level_up_effect == null:
		return
	_level_up_effect.play(new_level)

func _coop_session() -> CoopSession:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.coop_session

func _lobby() -> NakamaLobby:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.lobby

# Per-tick co-op outbound: ask the gate whether to broadcast our position,
# fire-and-forget the Nakama send if yes. Solo play (no session) is a
# single null-check no-op so the wire stays untouched. The gate's three
# rules (rate limit / delta / heartbeat) decide cadence — Player does
# not need to know the thresholds.
func _maybe_broadcast_position() -> void:
	var session := _coop_session()
	if session == null or session.position_broadcast_gate == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not session.position_broadcast_gate.try_broadcast(now, global_position):
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null or gs.lobby == null:
		return
	gs.lobby.send_position_async(now, global_position)

func _local_player_id() -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return ""
	return gs.local_player_id

func _offline_xp_tracker() -> OfflineXPTracker:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.offline_xp_tracker

func _cosmetic_inventory() -> CosmeticInventory:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.cosmetic_inventory

func _paid_unlocks() -> PaidUnlockInventory:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.paid_unlocks

func _play_attack_flash() -> void:
	if _visual == null:
		return
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.4, 1.4), 0.08)
	tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.12)
