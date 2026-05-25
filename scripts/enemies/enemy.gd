class_name Enemy
extends CharacterBody2D

signal died

@export var data: EnemyData
@export var detection_radius: float = EnemyAIState.DETECTION_RADIUS
@export var melee_range: float = EnemyAIState.MELEE_RANGE
@export var move_speed: float = EnemyAIState.CHASE_SPEED

var state: int = EnemyAIState.State.IDLE
var _attack_controller: AttackController
var _behavior: EnemyBehavior
# Cached chase target. Widened to Node2D in PRD #124 co-op TAUNT so a
# RemoteKitten (Node2D) can be the target on a receiving client where the
# caster has no local Player node. Contact damage gates on `is Player` so a
# RemoteKitten target produces a pursuit-only state (no damage on touch).
var _player_ref: Node2D = null
var _died_emitted: bool = false
# Angry Pigeon dive-bomb VFX (issue #161). Lazily-created Line2D parented to
# the enemy and populated each frame during a charge; cleared on completion.
# Kept on Enemy (not the behavior) so the pure-data behavior stays SceneTree-
# free and trivially testable — same separation as Player._apply_wet_tint.
var _pigeon_trail: Line2D = null
var _pigeon_was_charging: bool = false
# Rogue Roomba state (issue #162, retuned #262). Homing chase via the base
# _chase path; this flag is the only persistent roomba-side bookkeeping —
# it prevents the berserk tint/speed buff from re-applying once the entry
# count crosses 0→1.
var _roomba_berserk_applied: bool = false

const _TEXTURE_BY_KIND := {
	EnemyData.EnemyKind.ANGRY_PIGEON:         "res://assets/sprites/angry_pigeon_right.png",
	EnemyData.EnemyKind.ROGUE_ROOMBA:         "res://assets/sprites/rogue_roomba_right.png",
	EnemyData.EnemyKind.DOG_KNIGHT:           "res://assets/sprites/dog_knight_right.png",
	EnemyData.EnemyKind.CATNIP_DEALER:        "res://assets/sprites/catnip_dealer_right.png",
	EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE: "res://assets/sprites/haunted_spray_bottle_right.png",
}

func _ready() -> void:
	add_to_group("enemies")
	if data == null:
		data = EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	_attack_controller = AttackController.new()
	_attack_controller.cooldown = EnemyAIState.ATTACK_COOLDOWN
	# Bosses use the base (standard chase) behavior regardless of kind — they
	# already have a unique sprite and boosted stats; pigeon dive-bomb / roomba
	# bounce / etc. fight the room-confinement clamp and look wrong on the Vacuum.
	_behavior = EnemyBehavior.new() if data.is_boss else EnemyBehavior.for_kind(data.kind)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var path: String
		if data.is_boss:
			path = "res://assets/sprites/vacuum_boss.png"
		else:
			path = _TEXTURE_BY_KIND.get(data.kind, "res://assets/sprites/angry_pigeon_right.png")
		sprite.texture = load(path)
	# Haunted Spray Bottle (issue #165) floats over terrain — clear the
	# collision_mask so move_and_slide ignores wall tiles. The hurtbox stays
	# on the player-projectile layer so it remains hittable.
	if _behavior is HauntedSprayBottleBehavior and (_behavior as HauntedSprayBottleBehavior).ignores_wall_collision:
		collision_mask = 0
	# Floating HP bar (issue #247). Regular enemies only — boss enemies get
	# the dedicated HUD-pinned bar from #248, so attach() skips when
	# data.is_boss to avoid double presentation.
	EnemyHealthBar.attach(self)

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
	# Per-kind behavior may take exclusive control of motion this frame
	# (e.g., Angry Pigeon dive bomb, issue #161). When it does, skip the
	# state-machine match block so direct global_position writes from the
	# behavior aren't undone by _chase / move_and_slide. DEAD still runs
	# its queue_free path regardless.
	var motion_override := (
		_behavior != null
		and state != EnemyAIState.State.DEAD
		and _behavior.is_overriding_motion()
	)
	if not motion_override:
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
	# Per-kind behavior hook (issue #157). Runs after the base state machine so
	# kinds layer on top of chase/attack — overrides can read enemy.state /
	# velocity, spawn projectiles, drop hazards, etc. Default base impl no-ops.
	# Skipped on DEAD so behaviors don't tick a freed node.
	if _behavior != null and state != EnemyAIState.State.DEAD:
		_drive_rogue_roomba(delta)
		_drive_catnip_dealer(delta)
		_drive_haunted_spray_bottle(delta)
		_drive_dog_knight()
		_behavior.tick(delta, self)
		_observe_angry_pigeon()
		_observe_rogue_roomba()
		_observe_dog_knight()
		_observe_catnip_dealer()
		_observe_haunted_spray_bottle()
	if state != EnemyAIState.State.DEAD:
		_clamp_to_room_bounds()

# Advances the AI state machine and emits `died` on the live -> DEAD edge.
# Public so tests can drive transitions without instantiating into a
# SceneTree; the runtime path is _physics_process calling this once per
# physics frame.
func apply_state_update(distance: float) -> void:
	if data == null:
		return
	state = EnemyAIState.next_state(state, distance, data.hp, data.detection_radius)
	if state == EnemyAIState.State.DEAD and not _died_emitted:
		_died_emitted = true
		# Notify the per-kind behavior so it can publish death-edge state
		# (e.g., DogKnight's mead drop position) before the observer next runs.
		if _behavior is DogKnightBehavior:
			(_behavior as DogKnightBehavior).on_enemy_died(self)
			_observe_dog_knight()
		died.emit()

func _chase(target: Node2D) -> void:
	if target == null:
		velocity = Vector2.ZERO
	else:
		var dir := (target.global_position - global_position).normalized()
		velocity = dir * move_speed
		if dir != Vector2.ZERO and data != null:
			data.facing = dir
			var sprite := get_node_or_null("Sprite2D") as Sprite2D
			if sprite != null:
				sprite.flip_h = dir.x > 0.0
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
	elif dealt > 0:
		FloatingText.spawn(player, str(dealt), Color(1.0, 0.2, 0.2))

func flash_hit() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.0)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)

# Bridges AngryPigeonBehavior state edges to scene-tree side effects: motion
# trail Line2D during charge, FloorHazard slow zone and SPLAT FloatingText
# on completion. No-ops when the active behavior is not the pigeon's.
func _observe_angry_pigeon() -> void:
	if not (_behavior is AngryPigeonBehavior):
		return
	var apb := _behavior as AngryPigeonBehavior
	if apb.is_charging and not _pigeon_was_charging:
		_start_pigeon_trail()
	if apb.is_charging and _pigeon_trail != null:
		_pigeon_trail.add_point(global_position)
	if not apb.is_charging and _pigeon_was_charging:
		_end_pigeon_trail()
	_pigeon_was_charging = apb.is_charging
	if apb.pending_hazard_position != null:
		_spawn_pigeon_hazard(apb.pending_hazard_position)
		apb.pending_hazard_position = null
		FloatingText.spawn(self, "SPLAT")

func _start_pigeon_trail() -> void:
	if _pigeon_trail != null:
		return
	_pigeon_trail = Line2D.new()
	_pigeon_trail.width = 3.0
	_pigeon_trail.default_color = Color(1.0, 0.7, 0.7, 0.6)
	_pigeon_trail.top_level = true
	add_child(_pigeon_trail)
	_pigeon_trail.add_point(global_position)

func _end_pigeon_trail() -> void:
	if _pigeon_trail == null:
		return
	# Fade-out tween so the trail lingers briefly post-impact. queue_free is
	# called via the tween's finished signal so we don't strand a Line2D.
	var trail := _pigeon_trail
	_pigeon_trail = null
	var tween := create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, 0.25)
	tween.tween_callback(trail.queue_free)

func _spawn_pigeon_hazard(pos: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var hazard := FloorHazard.new()
	hazard.configure(
		AngryPigeonBehavior.HAZARD_DURATION,
		AngryPigeonBehavior.HAZARD_SLOW_PERCENT,
		0.0,
		AngryPigeonBehavior.HAZARD_RADIUS,
		AngryPigeonBehavior.HAZARD_COLOR
	)
	hazard.global_position = pos
	parent.add_child(hazard)

# Roomba motion driver (issue #162, retuned #262). Wall-bounce removed —
# homing chase is handled by the base CHASE path's `_chase(player)` call,
# which re-steers toward the player every physics frame using `move_speed`.
# Berserk's speed bump just scales move_speed (see _observe_rogue_roomba),
# which flows through `_chase` naturally. Hook retained as a no-op stub for
# symmetry with the other per-kind drivers / future hooks.
func _drive_rogue_roomba(_delta: float) -> void:
	pass

# Bridges RogueRoombaBehavior state edges to scene-tree side effects: damage
# trail FloorHazard spawn, berserk tint / speed buff / FloatingText.
func _observe_rogue_roomba() -> void:
	if not (_behavior is RogueRoombaBehavior):
		return
	var rrb := _behavior as RogueRoombaBehavior
	if rrb.pending_trail_spawn:
		_spawn_roomba_trail()
		rrb.pending_trail_spawn = false
	if rrb.berserk_entry_count > 0 and not _roomba_berserk_applied:
		_roomba_berserk_applied = true
		var sprite := get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			sprite.modulate = RogueRoombaBehavior.BERSERK_TINT
		move_speed *= RogueRoombaBehavior.BERSERK_SPEED_MULTIPLIER
		FloatingText.spawn(self, "BERSERK", Color(1.0, 0.2, 0.2))

# Supplies the player direction to DogKnightBehavior before its tick fires so
# the charge targets the player rather than a random angle.
func _drive_dog_knight() -> void:
	if not (_behavior is DogKnightBehavior):
		return
	# Aggro gate (issue #261). Belt-and-suspenders alongside the in-tick
	# cooldown gate: even if a stale cooldown carried over from a previous
	# aggro window, _drive_dog_knight refuses to begin a charge while IDLE.
	if not EnemyBehavior.is_aggroed(self):
		return
	var dkb := _behavior as DogKnightBehavior
	if not dkb.wants_to_charge():
		return
	var player := _find_player()
	var dir := Vector2.RIGHT
	if player != null:
		var to_player := player.global_position - global_position
		if to_player != Vector2.ZERO:
			dir = to_player.normalized()
	dkb.begin_charge(dir)

# Bridges DogKnightBehavior state edges to scene-tree side effects: "BURP"
# FloatingText on charge end, mead PowerUpPickup parented to the dungeon root
# at the death position. No-op when the active behavior is not the dog
# knight's.
func _observe_dog_knight() -> void:
	if not (_behavior is DogKnightBehavior):
		return
	var dkb := _behavior as DogKnightBehavior
	if dkb.pending_burp:
		FloatingText.spawn(self, "BURP", Color(0.8, 0.9, 0.4))
		dkb.pending_burp = false
	if dkb.pending_mead_drop_position != null:
		_spawn_mead_pickup(dkb.pending_mead_drop_position)
		dkb.pending_mead_drop_position = null

func _spawn_mead_pickup(pos: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var mead_type := KillRewardRouter.mead_drop_type_for(data)
	if mead_type == "":
		return
	var scene: PackedScene = load("res://scenes/power_up.tscn")
	if scene == null:
		return
	var pickup: PowerUpPickup = scene.instantiate()
	pickup.power_up_type = mead_type
	pickup.global_position = pos
	parent.call_deferred("add_child", pickup)

func _spawn_roomba_trail() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var hazard := FloorHazard.new()
	hazard.configure(
		RogueRoombaBehavior.TRAIL_DURATION,
		0.0,
		RogueRoombaBehavior.TRAIL_DAMAGE_PER_SEC,
		RogueRoombaBehavior.TRAIL_RADIUS,
		RogueRoombaBehavior.TRAIL_COLOR
	)
	hazard.global_position = global_position
	parent.add_child(hazard)

# Catnip Dealer motion override (issue #164). Reads the behavior's desired
# direction (preferred-range hold + flee inside FLEE_RANGE) and drives
# move_and_slide directly. Pure-data behavior stays SceneTree-free; the Enemy
# node owns the physics step — same separation as the roomba's _drive helper.
func _drive_catnip_dealer(_delta: float) -> void:
	pass

# Bridges CatnipDealerBehavior state edges to scene-tree side effects: spawns
# the catnip-bag EnemyProjectile when pending_fire_target is set, and the
# green-burst VFX + debuff FloatingText on projectile hit (via the on_hit
# callback closed over the chosen debuff type).
func _observe_catnip_dealer() -> void:
	if not (_behavior is CatnipDealerBehavior):
		return
	var cdb := _behavior as CatnipDealerBehavior
	if cdb.pending_fire_target != null:
		var target_pos: Vector2 = cdb.pending_fire_target
		var debuff_type: String = cdb.pick_debuff(cdb._rng)
		_spawn_catnip_projectile(target_pos, debuff_type)
		cdb.pending_fire_target = null
	if cdb.pending_burst_position != null:
		_spawn_catnip_burst(cdb.pending_burst_position)
		cdb.pending_burst_position = null

func _spawn_catnip_projectile(target_pos: Vector2, debuff_type: String) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var proj := EnemyProjectile.new()
	proj.position = global_position
	# Close over the dealer behavior so the on-hit observer publishes the burst
	# position back through pending_burst_position next frame.
	var behavior_ref := _behavior
	var on_hit := func(player_node):
		if behavior_ref is CatnipDealerBehavior:
			(behavior_ref as CatnipDealerBehavior).pending_burst_position = (
				player_node.global_position if player_node is Node2D else target_pos)
		_apply_catnip_debuff(player_node, debuff_type)
	proj.configure(
		target_pos,
		CatnipDealerBehavior.PROJECTILE_SPEED,
		CatnipDealerBehavior.PROJECTILE_RADIUS,
		CatnipDealerBehavior.PROJECTILE_COLOR,
		CatnipDealerBehavior.PROJECTILE_MAX_RANGE,
		on_hit
	)
	parent.add_child(proj)

func _apply_catnip_debuff(player_node, debuff_type: String) -> void:
	if player_node == null:
		return
	var label := CatnipDealerBehavior.floating_text_label(debuff_type)
	if debuff_type == CatnipDealerBehavior.DEBUFF_MISFIRE:
		if player_node.has_method("get") and player_node.get("data") != null:
			CatnipDealerBehavior.apply_misfire(player_node.get("data"))
	else:
		var effect := CatnipDealerBehavior.make_debuff_effect(debuff_type)
		if effect != null and player_node.has_method("apply_debuff"):
			player_node.apply_debuff(effect)
	if label != "" and player_node is Node:
		FloatingText.spawn(player_node, label, Color(0.5, 0.85, 0.3))

# Haunted Spray Bottle motion override (issue #165). Reads the behavior's
# desired direction (preferred-range hold) and drives move_and_slide directly.
func _drive_haunted_spray_bottle(_delta: float) -> void:
	pass

# Bridges HauntedSprayBottleBehavior state edges to scene-tree side effects:
# spawns the 3-projectile cone of EnemyProjectiles, the blue Line2D cone VFX,
# and the "WET" FloatingText on hit (via the on_hit callback).
func _observe_haunted_spray_bottle() -> void:
	if not (_behavior is HauntedSprayBottleBehavior):
		return
	var hsb := _behavior as HauntedSprayBottleBehavior
	if hsb.pending_fire_aim != null:
		var aim: Vector2 = hsb.pending_fire_aim
		var origin: Vector2 = hsb.pending_cone_origin if hsb.pending_cone_origin != null else global_position
		for d in HauntedSprayBottleBehavior.compute_cone_directions(aim):
			_spawn_spray_projectile(origin, d)
		_spawn_spray_cone_vfx(origin, aim)
		hsb.pending_fire_aim = null
		hsb.pending_cone_origin = null

func _spawn_spray_projectile(origin: Vector2, direction: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var proj := EnemyProjectile.new()
	proj.position = origin
	var target := origin + direction * HauntedSprayBottleBehavior.PROJECTILE_MAX_RANGE
	var on_hit := func(player_node):
		_apply_spray_wet(player_node)
	proj.configure(
		target,
		HauntedSprayBottleBehavior.PROJECTILE_SPEED,
		HauntedSprayBottleBehavior.PROJECTILE_RADIUS,
		HauntedSprayBottleBehavior.PROJECTILE_COLOR,
		HauntedSprayBottleBehavior.PROJECTILE_MAX_RANGE,
		on_hit
	)
	parent.add_child(proj)

func _apply_spray_wet(player_node) -> void:
	if player_node == null:
		return
	var effect := HauntedSprayBottleBehavior.make_wet_effect()
	if player_node.has_method("apply_debuff"):
		player_node.apply_debuff(effect)
	if player_node is Node:
		FloatingText.spawn(player_node, "WET", HauntedSprayBottleBehavior.PROJECTILE_COLOR)

func _spawn_spray_cone_vfx(origin: Vector2, aim: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var cone := Line2D.new()
	cone.top_level = true
	cone.width = 3.0
	cone.default_color = HauntedSprayBottleBehavior.CONE_VFX_COLOR
	var dirs := HauntedSprayBottleBehavior.compute_cone_directions(aim)
	var length := HauntedSprayBottleBehavior.CONE_VFX_LENGTH
	# Draw a fan: outer edge → origin → other outer edge so the segment forms
	# the cone silhouette in one Line2D node.
	cone.add_point(origin + dirs[1] * length)
	cone.add_point(origin)
	cone.add_point(origin + dirs[2] * length)
	parent.add_child(cone)
	var tween := cone.create_tween()
	tween.tween_property(cone, "modulate:a", 0.0, HauntedSprayBottleBehavior.CONE_VFX_DURATION)
	tween.tween_callback(cone.queue_free)

func _spawn_catnip_burst(pos: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var burst := Node2D.new()
	burst.global_position = pos
	var circle := Polygon2D.new()
	var points := PackedVector2Array()
	var seg := 16
	for i in range(seg):
		var a := TAU * float(i) / float(seg)
		points.append(Vector2(cos(a), sin(a)) * CatnipDealerBehavior.BURST_RADIUS)
	circle.polygon = points
	circle.color = CatnipDealerBehavior.BURST_COLOR
	burst.add_child(circle)
	parent.add_child(burst)
	var tween := burst.create_tween()
	tween.tween_property(circle, "modulate:a", 0.0, CatnipDealerBehavior.BURST_DURATION)
	tween.tween_callback(burst.queue_free)

func _clamp_to_room_bounds() -> void:
	if data == null or not data.room_bounds.has_area():
		return
	const MARGIN := 16.0
	var b: Rect2 = data.room_bounds
	global_position.x = clamp(global_position.x, b.position.x + MARGIN, b.end.x - MARGIN)
	global_position.y = clamp(global_position.y, b.position.y + MARGIN, b.end.y - MARGIN)

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
