class_name Player
extends CharacterBody2D

const _QuickbarScript = preload("res://scripts/character/quickbar.gd")
const _QuickbarControllerScript = preload("res://scripts/character/quickbar_controller.gd")
# PRD #223 weapon pivot system — all four kitten classes route attacks through
# the WeaponPivot + AttackChoreographer stack (slice 3 / issue #226 finished
# wiring sleepy and chonk). Cat-tier classes still null out of for_class and
# get no animated weapon, but they have no playable path yet either.
const _WeaponPivotScene = preload("res://scenes/weapon_pivot.tscn")

signal died
# Fired after KillRewardRouter.route_kill returns a non-null ItemData
# (PRD #73 / issue #80). HUD listens and surfaces the equip-or-bag
# prompt; Player is intentionally unaware of the UI so headless tests
# can drive the kill flow without instancing a CanvasLayer.
signal item_dropped(item: ItemData)
# Fired after a kill credits gold (base + Luck bonus) so the HUD can spawn a
# floating "+N Gold" label next to the player. Amount mirrors what landed in
# the ledger via KillRewardRouter.gold_for_kill.
signal gold_dropped(amount: int)

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
var _quickbar = null
var _quickbar_controller = null
var _power_ups: PowerUpManager
var _visual: Node2D
var _sprite: Sprite2D
var _wobble_time: float = 0.0
var _regen_accum: float = 0.0
var _mp_regen_accum: float = 0.0
var _died_emitted: bool = false
var _level_up_effect: LevelUpEffect
var _spell_light: PointLight2D
var _weapon_pivot: WeaponPivot = null
var _attack_choreographer: AttackChoreographer = null
# PRD #280 / issue #282: when unarmed, _try_attack routes here instead of
# the weapon choreographer. Eagerly built alongside _weapon_pivot so live
# unequip mid-dungeon doesn't have to allocate a controller on the first
# attack. Class-default null for cat-tier (no _weapon_pivot, no pounce —
# those classes have no playable path yet).
var _unarmed_attack: UnarmedAttack = null
# Tracks whether _hitbox is currently "live" per the choreographer's strike
# window. Pre-#223 the hitbox was always-on and _try_attack just walked
# overlapping areas; the choreographer now gates damage application to the
# strike phase so hits land when the swing is visibly mid-arc.
var _hitbox_strike_active: bool = false
var _coop_level_up_bound: bool = false
# Per-player phasing capability (issue #264). When true the player ignores
# the dedicated walls physics bit (EnemyBehavior.WALL_COLLISION_MASK from
# #263) and walks through dungeon wall tiles; when false that bit is added
# to collision_mask so move_and_slide is blocked by walls. Defaults to true
# so the pre-#264 pass-through behavior is preserved. Per-instance — the
# setter only mutates `self.collision_mask`, never any other Player in co-op.
var _can_phase_through_walls: bool = true
# Cached once in _ready; injectable via _inject_game_state() so tests can
# drive Player without a running GameState autoload.
var _game_state = null

func _inject_game_state(gs) -> void:
	_game_state = gs

# Phasing capability (issue #264). Public setter for the toggleable wall-
# collision capability. `enabled = true` means the player phases through
# walls (walls bit cleared from collision_mask); `false` engages collision
# (walls bit set). Idempotent — re-applying the same value leaves the mask
# in the expected single state, so callers don't need to guard.
func set_can_phase_through_walls(enabled: bool) -> void:
	_can_phase_through_walls = enabled
	if enabled:
		collision_mask &= ~EnemyBehavior.WALL_COLLISION_MASK
	else:
		collision_mask |= EnemyBehavior.WALL_COLLISION_MASK

func can_phase_through_walls() -> bool:
	return _can_phase_through_walls

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
		sprite.texture = load(SpriteHelper.path_for_class(data.character_class))
	_sprite = sprite
	_visual = sprite
	_level_up_effect = get_node_or_null("LevelUpEffect") as LevelUpEffect
	_spell_light = get_node_or_null("SpellLight") as PointLight2D
	_init_weapon_pivot()
	_init_quickbar()
	_bind_coop_level_up()

# PRD #280 / issue #281: the combat weapon is now driven by the player's
# actually equipped weapon (HeldWeaponResolver), not the class default. The
# WeaponPivot is spawned eagerly so we can swap textures/pose live on equip
# without re-instancing nodes; the choreographer is built lazily on the
# first armed refresh so unarmed kittens fall through to the existing
# no-animation melee path in _try_attack.
func _init_weapon_pivot() -> void:
	if data == null:
		return
	if WeaponDefinition.for_class(data.character_class) == null:
		# Cat-tier and other classes with no class weapon at all stay on the
		# pre-#223 no-pivot path.
		return
	_weapon_pivot = _WeaponPivotScene.instantiate()
	add_child(_weapon_pivot)
	_unarmed_attack = UnarmedAttack.new()
	_unarmed_attack.hitbox_enable_requested.connect(_on_strike_window_open)
	_unarmed_attack.hitbox_disable_requested.connect(_on_strike_window_close)
	_bind_inventory_loadout()
	_refresh_combat_weapon()

# Subscribe to ItemInventory.loadout_changed so equipping/unequipping mid-
# dungeon swaps the combat weapon live (PRD #280 user stories 7/8).
func _bind_inventory_loadout() -> void:
	var inv := _item_inventory()
	if inv == null:
		return
	if not inv.loadout_changed.is_connected(_on_loadout_changed):
		inv.loadout_changed.connect(_on_loadout_changed)

func _on_loadout_changed() -> void:
	_refresh_combat_weapon()
	_broadcast_player_info_for_equip_change()

# Slice 3 of PRD #328 (issue #331). Equip/unequip changes drive a fresh
# PLAYER_INFO broadcast so every peer's RemoteKitten can resolve the new
# weapon visual through the same HeldWeaponResolver path the local
# Player walked above. Solo (no lobby) is a single null-check no-op.
# Reuses send_player_info_async — the same wire path lobby create/join
# and the late-joiner rebroadcast use — so the receiving side has only
# one code path to maintain.
func _broadcast_player_info_for_equip_change() -> void:
	var lob := _lobby()
	if lob == null or lob.lobby_state == null:
		return
	var me := lob.lobby_state.find_player(lob.local_player_id)
	if me == null:
		return
	var inv := _item_inventory()
	var equipped: ItemData = inv.equipped_in(ItemData.Slot.WEAPON) if inv != null else null
	me.equipped_weapon_id = equipped.id if equipped != null else ""
	lob.send_player_info_async(me)

# Slice 4 of PRD #328 (issue #332), extended in slice 5 (issue #333).
# Co-op fan-out for the local swing or cast. Solo (no lobby) is a single
# null-check no-op so the wire stays untouched. `kind` discriminates the
# event type for the receiver — weapon_swing for melee, spell_cast for
# wizard primary (CAST attack_type), quickbar_cast for hotkey spells.
func _broadcast_attack(direction: Vector2, kind: String = NakamaLobby.ATTACK_KIND_WEAPON_SWING, spell_id: String = "") -> void:
	var lob := _lobby()
	if lob == null:
		return
	lob.send_attack_async(direction, kind, spell_id)

func _item_inventory() -> ItemInventory:
	if _game_state == null:
		return null
	return _game_state.get("item_inventory") as ItemInventory

# Re-resolve the held weapon and reconcile the WeaponPivot + AttackChoreographer
# with that state. Armed → pose the pivot, show the sprite, ensure the
# choreographer is built and pointing at the current definition. Unarmed →
# hide the weapon sprite and tear down the choreographer so _try_attack falls
# back to the direct melee pulse (the shake attack lands in slice 2).
func _refresh_combat_weapon() -> void:
	if _weapon_pivot == null or data == null:
		return
	var equipped: ItemData = null
	var inv := _item_inventory()
	if inv != null:
		equipped = inv.equipped_in(ItemData.Slot.WEAPON)
	var resolved := HeldWeaponResolver.resolve(equipped, data.character_class)
	var weapon_sprite := _weapon_pivot.get_node_or_null("Sprite2D") as Sprite2D
	if not resolved[HeldWeaponResolver.ARMED_KEY]:
		if weapon_sprite != null:
			weapon_sprite.visible = false
			weapon_sprite.texture = null
		_teardown_choreographer()
		return
	var def: WeaponDefinition = resolved[HeldWeaponResolver.DEFINITION_KEY]
	if def != null:
		_weapon_pivot.set_definition(def)
	var tex_path: String = resolved[HeldWeaponResolver.TEXTURE_KEY]
	if weapon_sprite != null:
		if tex_path != "":
			weapon_sprite.texture = load(tex_path)
			weapon_sprite.visible = true
		else:
			weapon_sprite.visible = false
			weapon_sprite.texture = null
	_ensure_choreographer(def)

func _ensure_choreographer(def: WeaponDefinition) -> void:
	if def == null:
		return
	if _attack_choreographer == null:
		_attack_choreographer = AttackChoreographer.new()
		_attack_choreographer.weapon_pivot = _weapon_pivot
		_attack_choreographer.hitbox_enable_requested.connect(_on_strike_window_open)
		_attack_choreographer.hitbox_disable_requested.connect(_on_strike_window_close)
		_attack_choreographer.strike_vfx_requested.connect(_on_strike_vfx)
	_attack_choreographer.definition = def

func _teardown_choreographer() -> void:
	if _attack_choreographer == null:
		return
	if _attack_choreographer.phase != AttackChoreographer.Phase.IDLE:
		_attack_choreographer.interrupt()
	_attack_choreographer = null
	_hitbox_strike_active = false

func get_quickbar():
	return _quickbar

# Slice 2 of PRD #210. Player owns one Quickbar + a child QuickbarController.
# The controller polls cast_slot_1..cast_slot_4 InputMap actions each frame
# and dispatches into Quickbar.fire_slot, which gates via Spell.cast
# (cooldown / MP / HP). On a successful cast the controller re-emits
# slot_fired(n), and Player applies the spell effect via SpellEffectResolver.
# Bootstraps from currently-unlocked spells in tree order so the slice is
# demoable before Slice 5 ships persistence.
func _init_quickbar() -> void:
	# Slice 5 of PRD #210: persistence owns the Quickbar lifecycle. When
	# GameState has already built one (real game path — either deserialized
	# from a save or freshly auto-filled in set_character), pick that up so
	# manual assignments and the migration result survive the scene swap.
	# Fall back to the slice-2 bootstrap for tests / paths that haven't
	# wired GameState — empty Quickbar gets seeded from unlocked spells.
	if _game_state != null and _game_state.get("current_quickbar") != null:
		_quickbar = _game_state.current_quickbar
	else:
		_quickbar = _QuickbarScript.new()
		if _spell_tree != null:
			for spell in _spell_tree.get_unlocked_spells():
				_quickbar.on_spell_unlocked(spell)
	_quickbar_controller = _QuickbarControllerScript.new()
	_quickbar_controller.name = "QuickbarController"
	_quickbar_controller.quickbar = _quickbar
	_quickbar_controller.caster = data
	add_child(_quickbar_controller)
	_quickbar_controller.slot_fired.connect(_on_slot_fired)

func _on_slot_fired(n: int) -> void:
	var spell = _quickbar.get_slot(n)
	if spell == null:
		return
	# Slice 5 of PRD #328 (issue #333): broadcast a quickbar_cast packet
	# so every peer's RemoteKitten can mirror the cast pose. Reaches this
	# point only after QuickbarController.slot_fired emits, which itself
	# only fires after Spell.cast() succeeds — so cooldown / MP / HP
	# gating already filtered the spam case (same shape as the slice-4
	# cooldown gate around _broadcast_attack). Solo path is a single
	# null-check inside _broadcast_attack.
	var facing: Vector2 = data.facing if data != null else Vector2.RIGHT
	_broadcast_attack(facing, NakamaLobby.ATTACK_KIND_QUICKBAR_CAST, spell.id)
	_apply_spell_effect(spell)

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
			var moving_left := input_dir.x < 0.0
			_sprite.flip_h = moving_left != SpriteHelper.faces_left(data.character_class)
			if _weapon_pivot != null:
				_weapon_pivot.set_facing(input_dir.x)
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
	if _attack_choreographer != null:
		_attack_choreographer.tick(delta)
	if _unarmed_attack != null:
		_unarmed_attack.tick(delta)
	if _quickbar_controller != null:
		_quickbar_controller._poll_inputs()

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

# Issue #160 / PRD #284. Enemies / hazards push a `(type_id, duration)`
# description so they control the timer without referencing effect class
# internals. Routes through the single PowerUpManager.apply path; the manager's
# refresh-not-stack semantics give re-hits a timer extension rather than a
# magnitude stack.
func apply_debuff(description: Dictionary) -> void:
	if data == null or description.is_empty():
		return
	var type_id: String = description.get("type_id", "")
	if type_id == "":
		return
	var duration: float = description.get("duration", -1.0)
	_power_ups.apply(type_id, data, duration)

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
	ProgressionSystem.add_xp(data, POWERUP_XP, _currency_ledger(), _spell_tree, _quickbar)
	if LevelUpEffect.is_real_level_up(old_level, data.level):
		_trigger_level_up_effect(data.level)

# Render-time sway while Ale is active, plus the unarmed bare-paw pounce
# (PRD #280) when in flight. Visual-only; doesn't affect physics velocity or
# hitbox position. The two effects sum so an unarmed drunk kitten still
# lunges on each attack on top of the ongoing sway. Resets to (0,0) when
# both are inactive.
func _apply_ale_wobble(delta: float) -> void:
	if _visual == null:
		return
	var ale_active := _power_ups.is_active(PowerUpEffect.TYPE_ALE)
	var shake_active := _unarmed_attack != null and _unarmed_attack.is_active()
	if ale_active:
		_wobble_time += delta
	else:
		_wobble_time = 0.0
	if ale_active or shake_active:
		var offset := Vector2.ZERO
		if ale_active:
			offset += AleEffect.get_movement_offset(_wobble_time)
		if shake_active:
			offset += _unarmed_attack.get_offset()
		_visual.position = offset
	elif _visual.position != Vector2.ZERO:
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
	if data == null or not data.is_alive():
		_regen_accum = 0.0
		_mp_regen_accum = 0.0
		return
	_tick_hp_regen(dt)
	_tick_mp_regen(dt)

func _tick_hp_regen(dt: float) -> void:
	if data.regeneration <= 0:
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

func _tick_mp_regen(dt: float) -> void:
	if data.mp_regen <= 0.0:
		_mp_regen_accum = 0.0
		return
	_mp_regen_accum += dt
	if _mp_regen_accum >= 1.0:
		_mp_regen_accum -= 1.0
		data.magic_points = mini(data.magic_points + int(data.mp_regen), data.max_mp)

func _try_attack() -> void:
	# PRD #85: dexterity shaves attack cooldown — re-read each call so
	# level-ups and power-ups propagate without a separate hook.
	if data != null:
		_attack_controller.cooldown = ATTACK_COOLDOWN / (1.0 + data.dexterity * 0.05)
	var now := Time.get_ticks_msec() / 1000.0
	if not _attack_controller.try_attack(now):
		return
	# Slice 4 of PRD #328 (issue #332). Broadcast the swing direction so
	# every peer's RemoteKitten can play the matching attack via the
	# existing AttackChoreographer path (no parallel co-op-only animation
	# code). Solo path is a single null-check no-op inside _broadcast_attack.
	# Fires here — after the cooldown gate but before the animation branch
	# — so a cooldown-rejected re-attack doesn't flood the wire.
	var attack_dir: Vector2 = data.facing if data != null else Vector2.RIGHT
	# Slice 5 of PRD #328 (issue #333): a CAST-type weapon attack
	# (wizard's primary) reads as a spell on the wire so receivers can
	# differentiate the cast pose from a melee swing. spell_id stays ""
	# because the wizard primary isn't backed by a Spell object — the
	# receiver's cast pose comes from its own choreographer's CAST
	# attack_type, not from a Spell lookup.
	var attack_kind: String = NakamaLobby.ATTACK_KIND_SPELL_CAST if _is_cast_attack() else NakamaLobby.ATTACK_KIND_WEAPON_SWING
	_broadcast_attack(attack_dir, attack_kind, "")
	# PRD #223: all four kitten classes route through the choreographer so
	# damage + VFX fire at the strike phase of a visible swing/cast. The
	# choreographer is null for character classes without a WeaponDefinition
	# (cat-tier etc.), in which case _try_attack falls through to a direct
	# melee damage pulse with no animation.
	if _attack_choreographer != null:
		var dir: Vector2 = data.facing if data != null else Vector2.RIGHT
		_attack_choreographer.start_attack(dir, _attack_choreographer.definition.attack_type)
		return
	# PRD #280 / issue #282: unarmed but class supports weapons — drive the
	# bare-paw pounce controller. It reuses the same strike-window signals as
	# the choreographer so damage still lands at the strike beat via
	# _on_strike_window_open → _apply_melee_damage. Facing drives the lunge.
	if _unarmed_attack != null:
		_unarmed_attack.start_attack(data.facing if data != null else Vector2.RIGHT)
		return
	_apply_melee_damage()

func _apply_melee_damage() -> void:
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

# Strike-window callbacks (PRD #223 user story 11). The hitbox is gated on
# the strike phase so the damage moment lines up with the visible swing —
# damage is applied once at strike open, mirroring the pre-#223 single-pulse
# semantics rather than a continuous overlap check across the whole strike
# window (which would risk multi-hits on a slow swing).
func _on_strike_window_open() -> void:
	_hitbox_strike_active = true
	# Slice 2 (PRD #223 / issue #225): wizard CAST routes damage through the
	# larger SpellHitbox rather than the melee Hitbox — the basic attack reads
	# as a spell pulse, not a swing.
	if _is_cast_attack():
		_apply_spell_basic_damage()
	else:
		_apply_melee_damage()

func _on_strike_window_close() -> void:
	_hitbox_strike_active = false

func _on_strike_vfx(_direction: Vector2) -> void:
	# Wizard CAST: fire the PointLight2D pulse synchronized with strike-phase
	# entry (PRD user story 13 — preserves existing spell juice but ties it
	# to the visible thrust apex). Slash VFX is spawned per-enemy inside the
	# damage methods, so no extra spawn needed for SWING here.
	if _is_cast_attack():
		_play_spell_flash()

func _is_cast_attack() -> bool:
	if _attack_choreographer == null or _attack_choreographer.definition == null:
		return false
	return _attack_choreographer.definition.attack_type == WeaponDefinition.AttackType.CAST

# Wizard basic-attack damage: same single-pulse-at-strike-open model as
# _apply_melee_damage, but targets the wider SpellHitbox and labels hits
# with the blue spell-damage color so it reads as a magical strike, not
# a melee hit.
func _apply_spell_basic_damage() -> void:
	if _spell_hitbox == null:
		return
	for area in _spell_hitbox.get_overlapping_areas():
		var node := area.get_parent()
		if node is Enemy and node.data != null and node.data.is_alive():
			var dealt := DamageResolver.apply(data, node.data)
			if dealt == 0 and data != null and data.attack > 0:
				FloatingText.spawn(node, "Miss")
			elif dealt > 0:
				FloatingText.spawn_at(node, str(dealt), Color(0.4, 0.6, 1.0))
				(node as Enemy).flash_hit()
			if not node.data.is_alive():
				_handle_enemy_killed(node)
				_record_meta_progress()
				SaveManager.save_from_state()

# Applies the effect of a spell that has already been cast (i.e. Spell.cast
# returned true inside Quickbar.fire_slot — cooldown started, MP/HP deducted).
# Selection moved out of Player in Slice 2; this method runs only the visual
# flash, SpellEffectResolver pass, floating-text damage labels, and post-kill
# bookkeeping. Same hitbox area as melee — keeps the "swing radius" model
# consistent across attack types until per-spell projectiles arrive.
func _apply_spell_effect(spell: Spell) -> void:
	if _spell_hitbox == null:
		return
	var enemy_nodes := _overlapping_enemy_nodes(_spell_hitbox)
	var enemy_data: Array = []
	for n in enemy_nodes:
		enemy_data.append(n.data)
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
		_spell_tree,
		_quickbar
	)
	if item_drop != null:
		item_dropped.emit(item_drop)
	var gold_amount := KillRewardRouter.gold_for_kill(data, enemy_data)
	if gold_amount > 0:
		gold_dropped.emit(gold_amount)
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
	# Sign of data.facing.x mirrors the local Player's last horizontal
	# input direction (updated in _physics_process). Sent every packet
	# with no edge detection so a receiver that joins mid-match has the
	# latest facing on the first packet it sees. See PRD #328 / #330.
	var facing_x: int = 0
	if data != null:
		facing_x = int(signf(data.facing.x))
	lob.send_position_async(now, global_position, facing_x)

func _local_player_id() -> String:
	return _game_state.local_player_id if _game_state != null else ""

func _offline_xp_tracker() -> OfflineXPTracker:
	return _game_state.offline_xp_tracker if _game_state != null else null

func _currency_ledger() -> CurrencyLedger:
	return _game_state.currency_ledger if _game_state != null else null

func _play_spell_flash() -> void:
	if _spell_light == null:
		return
	_spell_light.global_position = global_position
	_spell_light.energy = 0.0
	var tween := create_tween()
	tween.tween_property(_spell_light, "energy", 3.0, 0.05)
	tween.tween_property(_spell_light, "energy", 0.0, 0.3)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
