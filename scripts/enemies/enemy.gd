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
	# Bosses route through the same factory as standard mobs (PRD #518 user
	# story 42) — the old `is_boss` short-circuit onto the base behavior is
	# gone. for_data also stamps the behavior's ability loadout, so what a boss
	# does differently is data (AbilityLoadout), not a different code path.
	_behavior = EnemyBehavior.for_data(data)
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		var path: String
		if data.is_boss:
			# Per-floor sprite from BossRoster (stamped on EnemyData by
			# RoomSpawnPlanner; PRD #297, slice #301). Pick L/R by current
			# facing — Enemy facing defaults to DOWN before chase begins, so
			# x > 0 chooses right, otherwise left (mirrors _chase's flip_h).
			# Falls back to vacuum_boss for test fixtures / legacy planners
			# that left both paths empty.
			var prefer_right := data.facing.x > 0.0
			var roster_path := data.boss_sprite_right_path if prefer_right else data.boss_sprite_left_path
			if roster_path == "":
				roster_path = data.boss_sprite_left_path if prefer_right else data.boss_sprite_right_path
			if roster_path == "" or not ResourceLoader.exists(roster_path):
				# Slice #300 (HITL) is still producing the per-floor PNGs;
				# fall back to vacuum_boss when a path points at a not-yet-
				# delivered file so the runtime doesn't error on load().
				roster_path = "res://assets/sprites/vacuum_boss.png"
			path = roster_path
			# Per-floor boss PNGs ship at native ~48px; render at 1.5x so
			# they read as bosses next to ~48px mobs. vacuum_boss is already
			# 96px, so it keeps its 1.0 scale.
			if path != "res://assets/sprites/vacuum_boss.png":
				sprite.scale = Vector2(1.5, 1.5)
		else:
			path = _TEXTURE_BY_KIND.get(data.kind, "res://assets/sprites/angry_pigeon_right.png")
		sprite.texture = load(path)
		# Elite tint (PRD #376 / issue #381). Subtle warm-gold modulate so
		# elites read as distinct from same-kind non-elites at a glance —
		# pairs with the gold "Lv N" label from EnemyHealthBar. Bosses skip
		# the elite system entirely (their elite flag is never set), so
		# this branch is naturally boss-safe.
		if not data.is_boss and data.is_elite:
			sprite.modulate = EnemyHealthBar.ELITE_SPRITE_TINT
	# Wall collision wiring (issue #263). Normal kinds mask the dedicated walls
	# bit so move_and_slide is blocked by the dungeon painter's wall tiles;
	# HauntedSprayBottle (issue #165) opts out via wall_mask_for returning 0,
	# preserving the float-over-terrain contract. The hurtbox stays on the
	# player-projectile layer so the bottle remains hittable.
	collision_mask = EnemyBehavior.wall_mask_for(_behavior)
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
				# IDLE branch — drive idle wander via the behavior (PRD #391 /
				# slice #392). Behaviors that haven't opted in return Vector2.ZERO
				# (base impl) so this stays a no-op for them.
				if _behavior != null:
					velocity = _behavior.idle_velocity(self, delta)
				else:
					velocity = Vector2.ZERO
				move_and_slide()
	# Per-kind behavior hook (issue #157). Runs after the base state machine so
	# kinds layer on top of chase/attack — overrides can read enemy.state /
	# velocity, spawn projectiles, drop hazards, etc. Default base impl no-ops.
	# Skipped on DEAD so behaviors don't tick a freed node.
	if _behavior != null and state != EnemyAIState.State.DEAD:
		_drive_rogue_roomba(delta)
		_drive_haunted_spray_bottle(delta)
		_behavior.tick(delta, self)
		_pump_abilities(delta)
		_observe_angry_pigeon()
		_observe_rogue_roomba()
		_observe_catnip_dealer_burst()
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
		# Achievements (PRD #446 / issue #449): "kill mob" trigger. First
		# occurrence dedup is handled by AchievementService.record_event
		# itself (issue #447) — no local "already fired" flag needed here.
		var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
		if gs != null:
			gs.achievement_service.record_event("enemy_killed")
			# Tiered achievements (PRD #453 / issue #460): same call site also
			# feeds the cumulative "enemies_killed" counter for Mouse Patrol/
			# Certified Menace/Apex Predator (Probably).
			gs.achievement_service.increment_counter("enemies_killed", 1)
			# One-off (issue #471): Big Mouse Energy fires only on boss kills;
			# record_event's own idempotency handles "first boss kill only".
			if data.is_boss:
				gs.achievement_service.record_event("boss_killed")

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
	# Issue #498: the hooman has its own local HP pool (#497) and is a valid
	# taunt_targets chase target, so it takes contact damage directly via
	# DamageResolver rather than the Player/co-op routing below.
	if target is Hooman:
		var hooman := target as Hooman
		var now_h := Time.get_ticks_msec() / 1000.0
		if not _attack_controller.try_attack(now_h):
			return
		var dealt_h := DamageResolver.apply(data, hooman)
		if dealt_h == 0 and data != null and data.attack > 0:
			FloatingText.spawn(hooman, "Miss")
		elif dealt_h > 0:
			FloatingText.spawn(hooman, str(dealt_h), Color(1.0, 0.2, 0.2))
		return
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
	_apply_routed_damage(player)


# Shared tail for every enemy-on-player damage path — contact damage above
# and every danger-zone ability's commit payload via _apply_ability_damage
# below (issue #566). Callers own their own gating (attack cooldown for
# contact, the ability's own commit edge for abilities) and the `target is
# Player` / alive guard; this owns everything from that point on so a fix to
# routing or death handling reaches both paths by construction.
func _apply_routed_damage(player: Player) -> void:
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
		# PRD #328 slice 7 (issue #335): fan the hit through Player so it
		# broadcasts OP_PLAYER_HIT (co-op) for every peer's RemoteKitten
		# to play the matching hit-flash + knockback reaction. Solo path
		# is a single null-check no-op inside take_damage.
		player.take_damage(dealt, global_position)


# Generic ability pump (PRD #518 / tracer slice #533). Every enemy's abilities
# are driven through this one loop — no per-kind branch — so adding a move is a
# row in AbilityLoadout rather than another drive/observe pair in this file.
# The pump owns only the scene-side work an ability cannot do from a RefCounted:
# parenting the telegraph renderer and routing damage through CoopRouter.
#
# The per-kind _drive_* / _observe_* helpers below are the pre-archetype
# mechanics of the five standard mobs; issues #534-#545 convert them into
# archetypes and delete them. Until then their loadout is a single inert
# LegacyBehaviorAbility, so this loop is a no-op for them.
func _pump_abilities(delta: float) -> void:
	if _behavior == null or _behavior.abilities.is_empty():
		return
	for ability in _behavior.abilities:
		ability.tick(delta, self)
		if ability.is_overriding_motion():
			ability.drive_motion(delta, self)
		_consume_ability_zone(ability)
		_consume_ability_payload(ability)
	# One telegraph at a time: overlapping zones would make the colour language
	# unreadable, which is the whole point of the danger-zone system.
	for ability in _behavior.abilities:
		if ability.is_active():
			return
	for ability in _behavior.abilities:
		if ability.wants_to_fire():
			ability.begin(self)
			_consume_ability_zone(ability)
			return


# Parents a renderer for a freshly telegraphed zone. The renderer is handed the
# very shape object the ability will query for damage — what is drawn and what
# hits cannot drift — but keeps its own elapsed clock (see
# DangerZoneRenderer._elapsed) rather than reading the ability's, since the
# ability recycles that field for its next firing.
func _consume_ability_zone(ability) -> void:
	if ability.pending_zone == null:
		return
	var zone: DangerZoneShape = ability.pending_zone
	ability.pending_zone = null
	var parent := get_parent()
	if parent == null:
		return
	var renderer := DangerZoneRenderer.new()
	parent.add_child(renderer)
	renderer.configure(zone)


# Applies what an ability committed: damage on the caught player, and a cue for
# a player who got dragged. Routed here rather than inside the ability so co-op
# damage routing stays in exactly one place (see _try_contact_damage).
func _consume_ability_payload(ability) -> void:
	if ability.pending_hit_target != null:
		var hit = ability.pending_hit_target
		ability.pending_hit_target = null
		_apply_ability_damage(hit)
	if ability.pending_pull_target != null:
		var pulled = ability.pending_pull_target
		ability.pending_pull_target = null
		if pulled is Node:
			FloatingText.spawn(pulled, "PULL", Color(0.6, 0.8, 1.0))
	# Ambush/petrify (issue #536). Duck-typed via get() — only AmbushAbility
	# declares this field, so every other archetype's ability.get() here is a
	# safe no-op null (same pattern as _game_state.get("achievement_service")
	# elsewhere in the codebase).
	var petrify_target = ability.get("pending_petrify_target")
	if petrify_target != null:
		ability.set("pending_petrify_target", null)
		_apply_ability_petrify(petrify_target, ability)
	# Retreat and fire (issue #537 / #582). Duck-typed the same way — only
	# RetreatAndFireAbility declares this field. Both Old Lady Pearl and the
	# Catnip Dealer compose this same archetype, keyed apart by kind because
	# their commit payloads differ (Pearl's needle is plain damage; the
	# dealer's bag also rolls and applies a debuff).
	var fire_target = ability.get("pending_fire_target")
	if fire_target != null:
		ability.set("pending_fire_target", null)
		if data != null and data.kind == EnemyData.EnemyKind.CATNIP_DEALER:
			_spawn_catnip_dealer_projectile(fire_target)
		else:
			_spawn_pearl_projectile(fire_target)
	# Summon adds (issue #537). Duck-typed the same way — only
	# SummonAddsAbility declares this field.
	var summons = ability.get("pending_summons")
	if summons != null and not (summons as Array).is_empty():
		ability.set("pending_summons", [])
		for entry in summons:
			_spawn_summoned_add(entry, ability)


# Applies petrify through the same debuff seam the catnip bag / spray bottle
# use (player.apply_debuff), so the unified PowerUpManager path is the only
# place duration/refresh semantics live.
func _apply_ability_petrify(target, ability) -> void:
	if not (target is Player):
		return
	var player := target as Player
	if player.data == null or not player.data.is_alive():
		return
	var duration: float = PetrifyEffect.DEFAULT_DURATION
	if ability.has_method("petrify_duration"):
		duration = ability.petrify_duration()
	player.apply_debuff({"type_id": PowerUpEffect.TYPE_PETRIFY, "duration": duration})
	FloatingText.spawn(player, "PETRIFIED!", Color(0.75, 0.75, 0.8))


func _apply_ability_damage(target) -> void:
	if not (target is Player):
		return
	var player := target as Player
	if player.data == null or not player.data.is_alive():
		return
	_apply_routed_damage(player)


# Spawns Old Lady Pearl's knitting-needle projectile (issue #537). Reuses the
# same EnemyProjectile node the catnip bag / spray cone already use — no new
# projectile class — and routes the hit through _apply_ability_damage, the
# same co-op damage seam contact damage and the other archetypes share.
func _spawn_pearl_projectile(target_pos: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var proj := EnemyProjectile.new()
	proj.position = global_position
	proj.is_wall_at = _make_wall_predicate(parent)
	var on_hit := func(player_node):
		_apply_ability_damage(player_node)
	proj.configure(
		target_pos,
		RetreatAndFireAbility.PROJECTILE_SPEED,
		RetreatAndFireAbility.PROJECTILE_RADIUS,
		RetreatAndFireAbility.PROJECTILE_COLOR,
		RetreatAndFireAbility.PROJECTILE_MAX_RANGE,
		on_hit
	)
	parent.add_child(proj)


# Instantiates one of SummonAddsAbility's published entries as a real Enemy
# node (issue #537). Deterministic kind/position/id already came off the
# ability's seeded roll, so this is presentation only — no branching that
# could diverge between co-op clients. Wires the add's `died` signal back to
# `notify_add_died` so the summoner's cap tracks reality as adds fall.
func _spawn_summoned_add(entry: Dictionary, summon_ability) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var scene: PackedScene = load("res://scenes/enemy.tscn")
	if scene == null:
		return
	var kind: int = entry.get("kind", EnemyData.EnemyKind.ANGRY_PIGEON)
	var pos: Vector2 = entry.get("position", global_position)
	var add_data := EnemyData.make_new(kind)
	add_data.enemy_id = entry.get("enemy_id", "")
	add_data.spawn_position = pos
	var add := scene.instantiate() as Enemy
	add.data = add_data
	add.global_position = pos
	add.died.connect(func(): summon_ability.notify_add_died())
	parent.call_deferred("add_child", add)


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

# Bridges DogKnightBehavior state edges to scene-tree side effects: "BURP"
# FloatingText on charge end, mead PowerUpPickup parented to the dungeon root
# at the death position. No-op when the active behavior is not the dog
# knight's. The charge itself is now the composed TelegraphedChargeAbility
# (issue #581), driven by the generic ability pump rather than a per-kind
# drive branch here; this observer is only reached from the death edge in
# apply_state_update now, so pending_burp (never set post-migration) is
# effectively dormant while the mead-drop path it shares keeps working.
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

# Catnip Dealer kiting/fire cadence moved onto the composed
# RetreatAndFireAbility (issue #582) — the pre-migration `_drive_catnip_dealer`
# motion stub and the fire-target half of `_observe_catnip_dealer` are gone.
# What remains scene-side: routing the ability's pending_fire_target into the
# dealer's own projectile + debuff (below, from _consume_ability_payload) and
# polling the burst VFX handoff, which is still the behavior's own field since
# it fires off the projectile's on_hit callback rather than the ability pump.
func _observe_catnip_dealer_burst() -> void:
	if not (_behavior is CatnipDealerBehavior):
		return
	var cdb := _behavior as CatnipDealerBehavior
	if cdb.pending_burst_position != null:
		_spawn_catnip_burst(cdb.pending_burst_position)
		cdb.pending_burst_position = null

# Routes a fire request from the Catnip Dealer's composed RetreatAndFireAbility
# into the existing catnip-bag projectile + debuff-on-hit path (issue #582).
# The debuff roll itself is unchanged — still CatnipDealerBehavior.pick_debuff,
# seeded deterministically per enemy id (issue #534) — only the kiting/cadence
# that used to gate this moved onto the archetype.
func _spawn_catnip_dealer_projectile(target_pos: Vector2) -> void:
	if not (_behavior is CatnipDealerBehavior):
		return
	var cdb := _behavior as CatnipDealerBehavior
	var debuff_type: String = cdb.pick_debuff()
	_spawn_catnip_projectile(target_pos, debuff_type)

# Issue #265: build the wall-overlap predicate consumed by EnemyProjectile.
# Looks for the dungeon TileMap on the enemy's parent (main_scene's $TileMap)
# and queries get_cell_source_id against SOURCE_WALL at the projectile's
# current world position. Returns an empty Callable if no tilemap is reachable
# (bar room, tests, transient parents) — projectile then falls back to its
# hit / max_range predicates only, matching pre-#265 behavior.
func _make_wall_predicate(parent: Node) -> Callable:
	var tilemap := parent.get_node_or_null("TileMap") as TileMap
	if tilemap == null:
		return Callable()
	return func(world_pos: Vector2) -> bool:
		var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
		return tilemap.get_cell_source_id(0, cell) == DungeonTilemapPainter.SOURCE_WALL

func _spawn_catnip_projectile(target_pos: Vector2, debuff_type: String) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var proj := EnemyProjectile.new()
	proj.position = global_position
	proj.is_wall_at = _make_wall_predicate(parent)
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
		var description := CatnipDealerBehavior.make_debuff_description(debuff_type)
		if not description.is_empty() and player_node.has_method("apply_debuff"):
			player_node.apply_debuff(description)
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
	proj.is_wall_at = _make_wall_predicate(parent)
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
	var description := HauntedSprayBottleBehavior.make_wet_description()
	if player_node.has_method("apply_debuff"):
		player_node.apply_debuff(description)
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
	# Aggro on the nearest player avatar. The "taunt_targets" group is the one
	# place both the local Player (player.gd) and every remote co-op kitten
	# (remote_kitten.gd) register, so it doubles as the full set of player
	# avatars an enemy can chase. Selecting from it — rather than the local-only
	# "player" group — is what lets a party member's client see the enemy move
	# toward the player who actually triggered it. Contact damage stays local-
	# authoritative: _try_contact_damage no-ops on a non-Player target, so a
	# RemoteKitten gets chased but only its owning client resolves the hit.
	var nearest := _select_nearest_combatant(
		get_tree().get_nodes_in_group("taunt_targets"))
	if nearest != null:
		_player_ref = nearest
		return nearest
	# Group momentarily empty (everyone mid-despawn) — reuse the last known
	# target so an in-flight chase doesn't snap to a halt for a frame.
	if _player_ref != null and is_instance_valid(_player_ref):
		return _player_ref
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

# Picks the nearest live node from a candidate set by distance to this enemy,
# or null when the set is empty. Pulled out (like _select_taunt_target) so unit
# tests can drive selection without a populated SceneTree. Candidates come from
# the "taunt_targets" group — the union of the local Player and every remote
# co-op kitten, i.e. every player avatar an enemy may target.
func _select_nearest_combatant(candidates: Array) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for n in candidates:
		if n is Node2D and is_instance_valid(n):
			var d := global_position.distance_to((n as Node2D).global_position)
			if d < best_dist:
				best_dist = d
				best = n
	return best
