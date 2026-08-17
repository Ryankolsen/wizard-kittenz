class_name Hooman
extends CharacterBody2D

# Rented companion node (PRD #491, issue #496). Spawn/follow/lifecycle,
# HP/health bar (#497), mob aggro (#498), briefcase combat (#499), and burst
# heal (#500) — CHASE/ATTACK/HEAL are all fully wired states, driven by
# HoomanAIState (#493).
#
# Movement is plain position math (not move_and_slide) since the hooman is a
# non-colliding companion that drifts/snaps toward the player rather than
# navigating obstacles — this also keeps tick() callable headless (no
# SceneTree / physics server required), matching Enemy.apply_state_update's
# testable-without-scene-tree shape.

const RIGHT_TEXTURE_PATH := "res://assets/sprites/hooman_right.png"
const _WeaponPivotScene = preload("res://scenes/weapon_pivot.tscn")

# Follow tuning. Comfort radius is the "stand near the player" band; beyond
# LEASH_DISTANCE the hooman snaps back in rather than visibly catching up —
# covers cases like a floor transition teleport or the player sprinting
# through a doorway.
const COMFORT_RADIUS: float = 40.0
const LEASH_DISTANCE: float = 220.0
const FOLLOW_SPEED: float = 140.0

# Emitted when hp reaches 0 via take_damage, right before the node
# queue_frees itself (issue #497).
signal defeated

# Duck-typed stat block (hp/max_hp/attack/defense + take_damage/heal),
# matching EnemyData/CharacterData's shape so DamageResolver.apply works
# against a Hooman unmodified in either direction (issue #497).
@export var hp: int = 20
@export var max_hp: int = 20
# Flat, moderate attack stat (issue #499) — not scaled by player level/gear
# per the PRD decision. Comparable to a level-1 kitten's base attack (2-9
# across classes) rather than to mob attack (2-4), since the hooman is
# meant to meaningfully dent mob HP, not just tickle it.
@export var attack: int = 6
@export var defense: int = 0

# Wired by main_scene on spawn so take_damage can clear the rental on defeat
# without the node needing to reach back into GameState itself.
var rental_service: HoomanRentalService = null

var state: int = HoomanAIState.State.FOLLOW
var _active: bool = false

# Independent of the player's WeaponPivot/AttackChoreographer (issue #499) —
# the hooman always wields the briefcase preset, no equip/loadout system.
var _weapon_pivot: WeaponPivot = null
var _attack_choreographer: AttackChoreographer = null
# Nearest in-range mob, fed in each tick() call by main_scene (real Enemy
# reference, not just a distance) so the strike-window callback has
# something to apply DamageResolver.apply against.
var _current_target: Node = null

# HEAL-state visual telegraph (issue #503) — a looping particle glow shown
# for the entire time state == State.HEAL, including cooldown gaps between
# bursts, so the hooman doesn't look idle while "casting". Lazily created
# (mirrors _ensure_attack_choreographer) so headless tick()-only test
# fixtures with no _ready() call still have something to toggle.
var _heal_glow: CPUParticles2D = null

# Seconds remaining until the next burst heal is allowed (issue #500) —
# counts down every tick() regardless of state so the cooldown started by a
# heal keeps elapsing even if HEAL isn't re-entered immediately after.
var _heal_cooldown_remaining: float = 0.0


func _ready() -> void:
	add_to_group("hooman")
	# Issue #498: joining "taunt_targets" makes Enemy._select_nearest_combatant
	# (which already scans this group for Player/RemoteKitten targets) treat
	# the hooman as a valid chase target with zero changes to that method.
	add_to_group("taunt_targets")
	if get_node_or_null("Sprite2D") == null:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		if ResourceLoader.exists(RIGHT_TEXTURE_PATH):
			sprite.texture = load(RIGHT_TEXTURE_PATH)
		add_child(sprite)
	if get_node_or_null("CollisionShape2D") == null:
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = 16.0
		shape.shape = circle
		add_child(shape)
	HoomanHealthBar.attach(self)
	if _weapon_pivot == null:
		_weapon_pivot = _WeaponPivotScene.instantiate()
		add_child(_weapon_pivot)
	_ensure_attack_choreographer()
	_ensure_heal_glow()


# Matches EnemyData.take_damage's contract: reduces hp by amount (floored at
# 0) and returns the amount actually dealt. HP reaching 0 clears the rental
# (so the player must pay again even without a floor transition) and
# despawns the node.
func take_damage(amount: int) -> int:
	var dealt := mini(amount, hp)
	hp -= dealt
	if hp <= 0:
		_on_defeated()
	return dealt


# Matches EnemyData-shaped heal contract: increases hp by amount (capped at
# max_hp) and returns the amount actually healed.
func heal(amount: int) -> int:
	var healed := mini(amount, max_hp - hp)
	hp += healed
	return healed


func _on_defeated() -> void:
	if rental_service != null:
		rental_service.clear()
	defeated.emit()
	queue_free()


# Pure/headless-callable per-frame driver, same shape as
# Enemy.apply_state_update. Advances the AI state machine from
# HoomanAIState.next_state, then applies follow movement in FOLLOW, drifts
# toward the target in CHASE (without this the hooman would enter CHASE and
# just sit there, never actually reaching MELEE_RANGE to attack), drives the
# briefcase attack in ATTACK (issue #499), or applies a burst heal in
# HEAL (issue #500). `nearest_mob` is the actual Enemy reference (not just
# the distance already used for the state decision) so the strike window has
# a concrete target to damage; `player` is the Player-shaped node (exposing
# `.data`) the heal lands on and FloatingText spawns against. Both default to
# null so existing FOLLOW/CHASE-only callers keep working unchanged.
func tick(delta: float, player_pos: Vector2, nearest_mob_dist: float, player_hp_percent: float, is_active: bool, nearest_mob: Node = null, player: Node = null) -> void:
	_active = is_active
	_current_target = nearest_mob
	state = HoomanAIState.next_state(state, nearest_mob_dist, player_hp_percent, is_active)
	_ensure_heal_glow()
	_heal_glow.emitting = state == HoomanAIState.State.HEAL
	if _heal_cooldown_remaining > 0.0:
		_heal_cooldown_remaining -= delta
	if _attack_choreographer != null:
		_attack_choreographer.tick(delta)
	if state == HoomanAIState.State.FOLLOW:
		_apply_follow(delta, player_pos)
	elif state == HoomanAIState.State.CHASE:
		_apply_chase(delta)
	elif state == HoomanAIState.State.ATTACK:
		_try_attack()
	elif state == HoomanAIState.State.HEAL:
		_try_heal(player)


# Pure helper: velocity that would carry `pos` toward `player_pos` at
# `speed`. Zero when already at the player's position.
static func follow_velocity(pos: Vector2, player_pos: Vector2, speed: float = FOLLOW_SPEED) -> Vector2:
	var to_player := player_pos - pos
	if to_player.length_squared() <= 0.0:
		return Vector2.ZERO
	return to_player.normalized() * speed


# Drifts toward the player once outside COMFORT_RADIUS, snapping to just
# outside the comfort band when separation exceeds LEASH_DISTANCE (catch-up
# after a teleport, e.g. floor transition or bar exit) rather than visibly
# racing to close the gap.
func _apply_follow(delta: float, player_pos: Vector2) -> void:
	var to_player := player_pos - global_position
	var dist := to_player.length()
	if dist <= COMFORT_RADIUS:
		velocity = Vector2.ZERO
		return
	var dir := to_player / dist
	if dist > LEASH_DISTANCE:
		global_position = player_pos - dir * COMFORT_RADIUS
		velocity = Vector2.ZERO
		return
	velocity = dir * FOLLOW_SPEED
	global_position += velocity * delta
	_update_facing(dir)


# Drifts toward the currently tracked mob while in CHASE — without this the
# state machine correctly enters CHASE but the hooman never actually closes
# the gap to MELEE_RANGE, so it can sit in CHASE indefinitely and never
# attack. Falls back to holding position if the target is gone (mob died/
# despawned mid-chase) rather than drifting toward a stale position.
func _apply_chase(delta: float) -> void:
	if _current_target == null or not is_instance_valid(_current_target) or not (_current_target is Node2D):
		velocity = Vector2.ZERO
		return
	var target_pos: Vector2 = (_current_target as Node2D).global_position
	var to_target := target_pos - global_position
	var dist := to_target.length()
	if dist <= HoomanAIState.MELEE_RANGE:
		velocity = Vector2.ZERO
		return
	var dir := to_target / dist
	velocity = dir * FOLLOW_SPEED
	global_position += velocity * delta
	_update_facing(dir)


func _update_facing(dir: Vector2) -> void:
	if dir.x == 0.0:
		return
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.flip_h = dir.x < 0.0


# Lazily builds the choreographer so tick()/_try_attack() work headless in
# tests that construct a bare Hooman.new() (no _ready(), no WeaponPivot) —
# AttackChoreographer null-checks weapon_pivot throughout, so the swing
# state machine (and thus damage) still runs without a visual. Wires the
# pivot in once one exists (from _ready() in the real scene tree).
func _ensure_attack_choreographer() -> void:
	if _attack_choreographer == null:
		_attack_choreographer = AttackChoreographer.new()
		_attack_choreographer.definition = WeaponDefinition.briefcase()
		_attack_choreographer.hitbox_enable_requested.connect(_on_strike_window_open)
	if _attack_choreographer.weapon_pivot == null and _weapon_pivot != null:
		_attack_choreographer.weapon_pivot = _weapon_pivot
		_weapon_pivot.set_definition(_attack_choreographer.definition)


# Starts a briefcase swing toward the current target if the choreographer
# isn't already mid-swing — start_attack itself would clean-interrupt and
# restart, but ATTACK is re-entered every tick while in range, so gating on
# IDLE here keeps one swing per windup+strike+recovery cycle instead of
# restarting every frame.
func _try_attack() -> void:
	_ensure_attack_choreographer()
	if _attack_choreographer.phase != AttackChoreographer.Phase.IDLE:
		return
	var dir := Vector2.RIGHT
	if _current_target != null and is_instance_valid(_current_target) and _current_target is Node2D:
		var to_target: Vector2 = (_current_target as Node2D).global_position - global_position
		if to_target != Vector2.ZERO:
			dir = to_target.normalized()
	_attack_choreographer.start_attack(dir, WeaponDefinition.AttackType.SWING)


# Strike-window callback (mirrors player.gd's _on_strike_window_open ->
# _apply_melee_damage). Damages the nearest in-range mob tracked via
# _current_target through the same DamageResolver.apply duck-typed call
# player.gd uses, so a hooman kill drops the target's HP to 0 and the
# target's own AI tick (Enemy.apply_state_update) detects the live->DEAD
# edge and emits `died` exactly like a player kill — no parallel kill path.
func _apply_briefcase_damage() -> void:
	var target := _current_target
	if target == null or not is_instance_valid(target) or not ("data" in target):
		return
	var target_data = target.data
	if target_data == null or not target_data.is_alive():
		return
	if global_position.distance_to((target as Node2D).global_position) > HoomanAIState.MELEE_RANGE:
		return
	var dealt: int = DamageResolver.apply(self, target_data)
	if dealt == 0 and attack > 0:
		FloatingText.spawn(target, "Miss")
	elif dealt > 0:
		FloatingText.spawn_at(target, str(dealt), DamageKind.color_for(DamageKind.Kind.PHYSICAL))


func _on_strike_window_open() -> void:
	_apply_briefcase_damage()


# Lazily builds the looping glow particle node (issue #503), matching
# _ensure_attack_choreographer's pattern so headless Hooman.new() test
# fixtures with no _ready() call still have something for tick() to toggle.
# one_shot = false + emitting driven purely by state == HEAL in tick() is
# what makes this a continuous telegraph rather than a one-off flash.
func _ensure_heal_glow() -> void:
	if _heal_glow != null:
		return
	_heal_glow = get_node_or_null("HealGlow") as CPUParticles2D
	if _heal_glow == null:
		_heal_glow = CPUParticles2D.new()
		_heal_glow.name = "HealGlow"
		_heal_glow.amount = 12
		_heal_glow.lifetime = 0.6
		_heal_glow.one_shot = false
		_heal_glow.emitting = false
		_heal_glow.direction = Vector2(0, -1)
		_heal_glow.spread = 30.0
		_heal_glow.initial_velocity_min = 10.0
		_heal_glow.initial_velocity_max = 24.0
		_heal_glow.gravity = Vector2.ZERO
		_heal_glow.scale_amount_min = 2.0
		_heal_glow.scale_amount_max = 3.5
		_heal_glow.color = Color(0.2, 1.0, 0.4)
		add_child(_heal_glow)


# Test-facing accessor for the HEAL-state glow node (issue #503).
func get_heal_glow() -> CPUParticles2D:
	_ensure_heal_glow()
	return _heal_glow


# Public getter for the rental-paid-for-the-current-floor status set each
# tick() call (issue #504) — lets HealingBox gate litter-box healing on the
# same active/idle status the AI state machine already uses, without adding
# the hooman to the "player" group (that group is read by several unrelated
# systems per PRD #502's decision).
func is_active() -> bool:
	return _active


# Single cooldown-gated burst heal (issue #500) — a "pause to heal" per the
# PRD, not HealingBox's per-second drip accumulator. Applies via
# CharacterData.heal (same overheal-capped call HealingBox uses) and spawns
# the same "+N" green-text FloatingText.spawn feedback on the player.
func _try_heal(player: Node) -> void:
	if _heal_cooldown_remaining > 0.0:
		return
	if player == null or not is_instance_valid(player) or not ("data" in player):
		return
	var player_data = player.data
	if player_data == null:
		return
	var healed: int = player_data.heal(HoomanAIState.HEAL_BURST_AMOUNT)
	_heal_cooldown_remaining = HoomanAIState.HEAL_COOLDOWN
	if healed > 0:
		FloatingText.spawn(player, "+" + str(healed), Color(0.2, 1.0, 0.4))
