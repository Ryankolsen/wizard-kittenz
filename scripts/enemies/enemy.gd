class_name Enemy
extends CharacterBody2D

signal died

@export var data: EnemyData
@export var detection_radius: float = EnemyAIState.DETECTION_RADIUS
@export var melee_range: float = EnemyAIState.MELEE_RANGE
@export var move_speed: float = EnemyAIState.CHASE_SPEED

var state: int = EnemyAIState.State.IDLE
var _attack_controller: AttackController
# Cached chase target. Widened to Node2D in PRD #124 co-op TAUNT so a
# RemoteKitten (Node2D) can be the target on a receiving client where the
# caster has no local Player node. Contact damage gates on `is Player` so a
# RemoteKitten target produces a pursuit-only state (no damage on touch).
var _player_ref: Node2D = null
var _died_emitted: bool = false

const _TEXTURE_BY_KIND := {
	EnemyData.EnemyKind.SLIME: "res://assets/sprites/slime.png",
	EnemyData.EnemyKind.BAT:   "res://assets/sprites/bat.png",
	EnemyData.EnemyKind.RAT:   "res://assets/sprites/bat.png",
}

func _ready() -> void:
	add_to_group("enemies")
	if data == null:
		data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	_attack_controller = AttackController.new()
	_attack_controller.cooldown = EnemyAIState.ATTACK_COOLDOWN
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var path: String = _TEXTURE_BY_KIND.get(data.kind, "res://assets/sprites/slime.png")
		sprite.texture = load(path)

func _physics_process(delta: float) -> void:
	if data == null:
		return
	# Decay any active TAUNT before resolving target so an expired taunt this
	# frame falls through to the default group-based lookup.
	data.tick_taunt(delta)
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

func _chase(target: Node2D) -> void:
	if target == null:
		velocity = Vector2.ZERO
	else:
		var dir := (target.global_position - global_position).normalized()
		velocity = dir * move_speed
		if dir != Vector2.ZERO and data != null:
			data.facing = dir
	move_and_slide()

# Contact damage gated by AttackController so a melee-range enemy doesn't
# drain the player's HP every physics frame. Same cooldown shape as the
# player's swing — DamageResolver duck-types over both sides.
func _try_contact_damage(target: Node2D) -> void:
	# Co-op TAUNT can park us on a RemoteKitten (Node2D, no .data) when the
	# caster is on another client. Pursue without damaging — the casting
	# client's own Enemy still resolves contact damage against the caster.
	if not (target is Player):
		return
	var player := target as Player
	if player.data == null or not player.data.is_alive():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _attack_controller.try_attack(now):
		return
	# PRD #116: route incoming damage through CoopRouter so that in a
	# co-op session the hit lands on the local member's effective_stats
	# (the scaled HP pool the HUD reads) rather than real_stats. Solo
	# path (null session) is a single null-check no-op that falls
	# through to DamageResolver against player.data directly.
	var session: CoopSession = null
	var pid := ""
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		session = gs.coop_session
		pid = gs.local_player_id
	var dealt := CoopRouter.apply_damage(session, data, player.data, pid)
	# PRD #85 / issue #91: enemy-on-player misses surface a floating
	# "Miss" near the player. Player evasion is the dominant contributor
	# at the player side — same indicator covers HitResolver miss and
	# evade because DamageResolver collapses both to 0.
	if dealt == 0 and data != null and data.attack > 0:
		FloatingText.spawn(player, "Miss")

func flash_hit() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.0)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)

func _find_player() -> Node2D:
	var nodes := get_tree().get_nodes_in_group("player")
	# Chonk Taunt (PRD #124): an active TAUNT fixates this enemy on the
	# caster's node, bypassing the nearest-player heuristic. Two resolver
	# paths cover the two identity hooks that may be present:
	#   1. taunt_target (CharacterData ref) — local-cast clients stamp this
	#      and the caster is always a local Player node.
	#   2. taunt_source_id (network player_id) — receive-side stamp from
	#      RemoteTauntApplier. Caster has no local CharacterData; matching
	#      node is a RemoteKitten in the "taunt_targets" group.
	# Falls through if neither path finds a live match (caster despawned).
	var taunted: Node2D = _select_taunt_target(nodes)
	if taunted == null:
		taunted = _select_taunt_target_by_id(
			get_tree().get_nodes_in_group("taunt_targets"))
	if taunted != null:
		_player_ref = taunted
		return taunted
	if _player_ref != null and is_instance_valid(_player_ref):
		return _player_ref
	if nodes.is_empty():
		return null
	var p := nodes[0]
	if p is Player:
		_player_ref = p
		return p
	return null

# Picks the Player node whose CharacterData matches the active taunt target,
# or null when not taunted / no live match. Pulled out for unit tests so they
# can drive the selection without a populated scene tree.
func _select_taunt_target(candidates: Array) -> Player:
	if data == null or not data.is_taunted() or data.taunt_target == null:
		return null
	for n in candidates:
		if n is Player and n.data == data.taunt_target:
			return n
	return null

# Picks the taunt-targets-group node whose `player_id` matches the stamped
# `taunt_source_id`, or null when not taunted / no live match. Used on the
# receiving co-op client where the caster's CharacterData object doesn't
# exist locally (so _select_taunt_target's ref-match would always miss) and
# the caster is rendered as a RemoteKitten instead of a Player node.
func _select_taunt_target_by_id(candidates: Array) -> Node2D:
	if data == null or not data.is_taunted() or data.taunt_source_id == "":
		return null
	for n in candidates:
		if n is Node2D and "player_id" in n and n.player_id == data.taunt_source_id:
			return n
	return null
