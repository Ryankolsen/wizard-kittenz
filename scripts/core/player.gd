class_name Player
extends CharacterBody2D

signal died
# Fired after KillRewardRouter.route_kill returns a non-null ItemData
# (PRD #73 / issue #80). HUD listens and surfaces the equip-or-bag
# prompt; Player is intentionally unaware of the UI so headless tests
# can drive the kill flow without instancing a CanvasLayer.
signal item_dropped(item: ItemData)

const ATTACK_COOLDOWN: float = 0.4
# PRD #52 power-up pickup XP. Awarded on every collect_power_up call.
# Co-op routes through the party-split broadcaster (each member receives
# floor(POWERUP_XP / party_size)); solo applies directly to data.
const POWERUP_XP: int = 25

@export var speed: float = 60.0
@export var data: CharacterData
# Cross-client identity for this Player (PRD #124 co-op TAUNT). Populated from
# GameState.local_player_id in _ready when blank; the @export keeps a setter
# seam open for tests that drive the value without an autoload. Read by
# Enemy._select_taunt_target_by_id when EnemyData.taunt_source_id is stamped
# (the receive-side path where the caster's CharacterData object doesn't exist
# locally). Empty string is the "no co-op identity" sentinel and never matches
# a stamped source id.
@export var player_id: String = ""

var _attack_controller: AttackController
var _hitbox: Area2D
var _spell_hitbox: Area2D
var _spell_tree: SkillTree
var _power_ups: PowerUpManager
var _visual: Node2D
var _sprite: Sprite2D
var _wobble_time: float = 0.0
var _regen_accum: float = 0.0
var _died_emitted: bool = false
var _level_up_effect: LevelUpEffect
var _spell_light: PointLight2D
var _coop_level_up_bound: bool = false
# Cached once in _ready; injectable via _inject_game_state() so tests can
# drive Player without a running GameState autoload.
var _game_state = null

func _inject_game_state(gs) -> void:
	_game_state = gs

func _ready() -> void:
	if _game_state == null:
		_game_state = get_node_or_null("/root/GameState")
	add_to_group("player")
	add_to_group("taunt_targets")
	# "players" group is the lookup surface RemoteHealApplier (issue #146)
	# walks to resolve heal_applied(target_id) → local Player node.
	# Membership is a node-level concern, not a CharacterData one — the
	# applier needs to flip live HP / buff state, which lives on the
	# Player + its data, not on a bare CharacterData reference.
	add_to_group("players")
	if player_id == "":
		player_id = _local_player_id()
	if data == null:
		if _game_state != null and _game_state.current_character != null:
			data = _game_state.current_character
			_spell_tree = _game_state.skill_tree
	if data == null:
		data = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	# Mirror the player_id onto data so SpellEffectResolver can stamp
	# heal_applied(target_id) without a node reference (the resolver
	# operates on CharacterData arrays, not Player nodes).
	if data.player_id == "":
		data.player_id = player_id
	# data.speed is now the source of truth (per-class baseline). The @export
	# stays as an editor-time override for scene-only iteration.
	if data.speed > 0.0:
		speed = data.speed
	_attack_controller = AttackController.new()
	_attack_controller.cooldown = ATTACK_COOLDOWN
	_hitbox = get_node_or_null("Hitbox")
	_spell_hitbox = get_node_or_null("SpellHitbox")
	_power_ups = PowerUpManager.new()
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = load("res://assets/sprites/wizard_kitten.png")
	_sprite = sprite
	_visual = sprite
	_level_up_effect = get_node_or_null("LevelUpEffect") as LevelUpEffect
	_spell_light = get_node_or_null("SpellLight") as PointLight2D
	_bind_coop_level_up()

func _physics_process(delta: float) -> void:
	if data != null and not data.is_alive():
		_check_died()
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# ConfusionEffect (#160) flips the input vector while active. Done here
	# rather than inside compute_velocity so facing / sprite flip below also
	# read the reversed direction — confused players visibly face "wrong".
	if data != null and data.is_confused():
		input_dir = -input_dir
	# Re-read data.speed each frame so PowerUpManager mutations (Catnip / Wet
	# / Slowness) propagate without needing a Player.gd hook.
	if data != null and data.speed > 0.0:
		speed = data.speed
	velocity = compute_velocity(input_dir, speed)
	# Track facing only when actually moving so a stationary kitten keeps its
	# last-known direction (relevant for backstab targeting).
	if input_dir != Vector2.ZERO:
		data.facing = input_dir.normalized()
		if _sprite != null and input_dir.x != 0.0:
			_sprite.flip_h = input_dir.x > 0.0
	move_and_slide()
	_tick_spells(delta)
	if data != null:
		var regen_healed := data.tick_buffs(delta)
		if regen_healed > 0:
			FloatingText.spawn(self, str(regen_healed), Color(0.2, 1.0, 0.4))
	_tick_regeneration(delta)
	_power_ups.tick(delta)
	_apply_ale_wobble(delta)
	_apply_wet_tint()
	_maybe_broadcast_position()
	if Input.is_action_just_pressed("attack"):
		_try_attack()
	if Input.is_action_just_pressed("cast_spell"):
		_try_cast_spell()

# Emit `died` exactly once when hp first reaches zero. The death-screen
# revive button calls CoopRouter.revive, which sets hp back above
# zero — _died_emitted resets nowhere, but a successful revive simply
# means data.is_alive() goes true again so this branch is skipped.
func _check_died() -> void:
	if _died_emitted:
		return
	_died_emitted = true
	died.emit()

func collect_power_up(type_id: String) -> void:
	_power_ups.apply(type_id, data)
	_award_power_up_xp()

# Issue #160. Enemies / hazards push a constructed effect (so they control the
# duration) instead of a string id — debuffs aren't in the PowerUpEffect.make
# factory because they aren't player-side pickups. Refresh-not-stack semantics
# match collect_power_up: re-applying the same debuff type extends the timer
# rather than stacking the magnitude.
func apply_debuff(effect: PowerUpEffect) -> void:
	if data == null or effect == null:
		return
	_power_ups.apply_effect(effect, data)

# PRD #52: every power-up pickup pays POWERUP_XP. Co-op fans through
# the same broadcaster-split path as kills so each party member gets
# floor(POWERUP_XP / party_size); solo applies directly to data.
func _award_power_up_xp() -> void:
	if data == null:
		return
	var session := _coop_session()
	var local_id := _local_player_id()
	if session != null and session.is_routing_ready():
		if not _coop_level_up_bound:
			_bind_coop_level_up()
		var per_player := KillRewardRouter.xp_per_player(
			POWERUP_XP, session.xp_broadcaster.player_count())
		session.xp_broadcaster.on_enemy_killed(per_player, local_id)
		return
	var old_level := data.level
	ProgressionSystem.add_xp(data, POWERUP_XP, _currency_ledger(), _spell_tree)
	if LevelUpEffect.is_real_level_up(old_level, data.level):
		_trigger_level_up_effect(data.level)

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

# Render-time blue tint while the wet debuff (#160) is active. Visual-only; the
# speed reduction is handled by the effect itself mutating data.speed. Clean
# restore on expiry mirrors _apply_ale_wobble.
const _WET_TINT := Color(0.55, 0.75, 1.0, 1.0)
func _apply_wet_tint() -> void:
	if _sprite == null:
		return
	if _power_ups.is_active(PowerUpEffect.TYPE_WET):
		if _sprite.modulate != _WET_TINT:
			_sprite.modulate = _WET_TINT
	elif _sprite.modulate != Color.WHITE:
		_sprite.modulate = Color.WHITE

func _tick_spells(dt: float) -> void:
	if _spell_tree == null:
		return
	# PRD #85: magic_attack shaves spell cooldowns. Re-derive each frame so
	# level-ups / item swaps propagate without a separate hook (mirrors how
	# dexterity rewrites _attack_controller.cooldown in _try_attack).
	var ma := 0
	if data != null:
		ma = data.magic_attack
	var scale := 1.0 + float(ma) * 0.03
	for spell in _spell_tree.get_unlocked_spells():
		spell.cooldown = spell.base_cooldown / scale
		spell.tick(dt)

func _tick_regeneration(dt: float) -> void:
	if data == null or data.regeneration <= 0 or not data.is_alive():
		_regen_accum = 0.0
		return
	# Suppress passive regen while Regen Snooze (GROUP_REGEN) is active so the
	# active-buff HoT doesn't stack on top of the per-class passive (#144).
	if data.has_active_buff(CharacterData.BUFF_GROUP_REGEN):
		_regen_accum = 0.0
		return
	_regen_accum += dt
	if _regen_accum >= 1.0:
		_regen_accum -= 1.0
		data.heal(data.regeneration)

func _try_attack() -> void:
	# PRD #85: dexterity shaves attack cooldown — re-read each call so
	# level-ups and power-ups propagate without a separate hook.
	if data != null:
		_attack_controller.cooldown = ATTACK_COOLDOWN / (1.0 + data.dexterity * 0.05)
	var now := Time.get_ticks_msec() / 1000.0
	if not _attack_controller.try_attack(now):
		return
	_play_attack_flash()
	if _hitbox == null:
		return
	for area in _hitbox.get_overlapping_areas():
		var node := area.get_parent()
		if node is Enemy and node.data != null and node.data.is_alive():
			var dealt := DamageResolver.apply(data, node.data)
			# PRD #85 / issue #91: surface "Miss" on a failed physical hit.
			# DamageResolver returns 0 on miss (HitResolver) or evade
			# (target.evasion); both render the same indicator. Skip when
			# attacker had no attack to begin with so we don't spam Miss
			# for zero-attack contact cases.
			if dealt == 0 and data != null and data.attack > 0:
				FloatingText.spawn(node, "Miss")
			elif dealt > 0:
				FloatingText.spawn_at(node, str(dealt), Color(1.0, 0.2, 0.2))
				(node as Enemy).flash_hit()
				SlashEffect.spawn(node, data.facing if data != null else Vector2.RIGHT)
			if not node.data.is_alive():
				_handle_enemy_killed(node)
				_record_meta_progress()
				SaveManager.save_from_state()

# Cast the first ready unlocked spell. Same hitbox area as melee — keeps the
# "swing radius" model consistent across attack types until #11 introduces
# per-spell projectiles/areas.
func _try_cast_spell() -> void:
	if _spell_tree == null or _spell_hitbox == null:
		return
	var enemy_nodes := _overlapping_enemy_nodes(_spell_hitbox)
	var enemy_data: Array = []
	for n in enemy_nodes:
		enemy_data.append(n.data)
	for spell in _spell_tree.get_unlocked_spells():
		if not spell.cast(data):
			continue
		_play_spell_flash()
		var hp_self_before := data.hp if data != null else 0
		var hp_before: Array = []
		for n in enemy_nodes:
			hp_before.append(n.data.hp if n.data != null else 0)
		SpellEffectResolver.apply(spell, data, enemy_data, null, _taunt_broadcaster(), _local_player_id(), _heal_broadcaster())
		if data != null:
			var self_healed := data.hp - hp_self_before
			if self_healed > 0:
				FloatingText.spawn(self, str(self_healed), Color(0.2, 1.0, 0.4))
		for i in range(enemy_nodes.size()):
			var n: Enemy = enemy_nodes[i]
			if n.data == null:
				continue
			var dealt: int = hp_before[i] - n.data.hp
			if dealt > 0:
				FloatingText.spawn_at(n, str(dealt), Color(0.4, 0.6, 1.0))
		var any_killed := false
		for n in enemy_nodes:
			if n.data != null and not n.data.is_alive():
				_handle_enemy_killed(n)
				any_killed = true
		if any_killed:
			_record_meta_progress()
			SaveManager.save_from_state()
		return

func _handle_enemy_killed(node: Enemy) -> void:
	_award_kill_xp(node.data)
	node.queue_free()

func _overlapping_enemy_nodes(hitbox: Area2D = null) -> Array:
	var box := hitbox if hitbox != null else _hitbox
	var out: Array = []
	for area in box.get_overlapping_areas():
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
	return _game_state.meta_tracker if _game_state != null else null

# Routes a local kill to the right reward path: solo applies XP locally
# and tallies into the offline counter; co-op broadcasts XP via the
# active session. The branch itself lives in KillRewardRouter so it can
# be tested without booting a Player scene. Null enemy_data degrades to
# a no-op (defensive for a future kill source that doesn't pass the
# data, e.g. DoT spells).
func _award_kill_xp(enemy_data: EnemyData) -> void:
	if data == null or enemy_data == null:
		return
	# Bind before route_kill so the co-op level_up signal (which fires
	# synchronously inside xp_broadcaster.on_enemy_killed) is already
	# connected when it emits. Binding after route_kill caused the first
	# level-up in a session to silently miss the effect.
	if not _coop_level_up_bound:
		_bind_coop_level_up()
	var old_level := data.level
	var item_drop := KillRewardRouter.route_kill(
		data,
		enemy_data,
		_coop_session(),
		_local_player_id(),
		_offline_xp_tracker(),
		_lobby(),
		_currency_ledger(),
		null,
		_spell_tree
	)
	if item_drop != null:
		item_dropped.emit(item_drop)
	if LevelUpEffect.is_real_level_up(old_level, data.level):
		_trigger_level_up_effect(data.level)

func _bind_coop_level_up() -> void:
	if _coop_level_up_bound:
		return
	var session := _coop_session()
	if session == null or session.xp_subscriber == null:
		return
	if not session.xp_subscriber.level_up.is_connected(_on_coop_level_up):
		session.xp_subscriber.level_up.connect(_on_coop_level_up)
	_coop_level_up_bound = true

func _on_coop_level_up(old_level: int, new_level: int) -> void:
	if LevelUpEffect.is_real_level_up(old_level, new_level):
		_trigger_level_up_effect(new_level)

func _trigger_level_up_effect(new_level: int) -> void:
	if _level_up_effect == null:
		return
	_level_up_effect.play(new_level)

func _taunt_broadcaster() -> TauntBroadcaster:
	var session := _coop_session()
	if session == null:
		return null
	return session.taunt_broadcaster

func _heal_broadcaster():
	var session := _coop_session()
	if session == null:
		return null
	return session.heal_broadcaster

func _coop_session() -> CoopSession:
	return _game_state.coop_session if _game_state != null else null

func _lobby() -> NakamaLobby:
	return _game_state.lobby if _game_state != null else null

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
	var lob := _lobby()
	if lob == null:
		return
	lob.send_position_async(now, global_position)

func _local_player_id() -> String:
	return _game_state.local_player_id if _game_state != null else ""

func _offline_xp_tracker() -> OfflineXPTracker:
	return _game_state.offline_xp_tracker if _game_state != null else null

func _currency_ledger() -> CurrencyLedger:
	return _game_state.currency_ledger if _game_state != null else null

func _play_attack_flash() -> void:
	if _visual == null:
		return
	var swing := 1.0 if data == null or data.facing.x >= 0.0 else -1.0
	var tween := create_tween()
	tween.tween_property(_visual, "rotation", -0.2 * swing, 0.05)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "rotation", 0.3 * swing, 0.06)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "rotation", 0.0, 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _play_spell_flash() -> void:
	if _spell_light == null:
		return
	_spell_light.global_position = global_position
	_spell_light.energy = 0.0
	var tween := create_tween()
	tween.tween_property(_spell_light, "energy", 3.0, 0.05)
	tween.tween_property(_spell_light, "energy", 0.0, 0.3)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
