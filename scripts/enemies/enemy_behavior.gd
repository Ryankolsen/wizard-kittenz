class_name EnemyBehavior
extends RefCounted

# Lazily seeded from enemy_id so wander is reproducible per spawn. Untyped to
# keep load order resilient. Shared by idle_velocity below — every kind that
# wanders owns exactly one profile instance for its lifetime.
var _wander_profile = null  # WanderProfile

# Per-kind tick hook (issue #157). The Enemy node calls `behavior.tick(delta, self)`
# each physics frame after the base state machine resolves; subclasses override
# `tick` to layer kind-specific behavior (dive bomb charge, wall bounce, water
# cone, etc.) on top of the shared chase/attack baseline. Default is a no-op so
# kinds without a registered behavior are safe and the wiring is the contract.
#
# Factory `for_kind` is exhaustive over EnemyData.EnemyKind so any kind — even
# one without a registered subclass yet — returns a non-null base instance.
# Per-kind subclasses land in follow-up issues (#161-#165).

# Dedicated walls physics layer bit (issue #263). The dungeon painter stamps
# its wall collision polygons onto this bit so enemies can mask it without
# colliding with actor-layer bodies (bit 0). Players intentionally do NOT
# mask this bit — they walk through walls until #264 adds toggleable phasing.
# Bar room (scripts/dungeon/bar_room.gd) uses the same bit so the rule is
# uniform across both tile sources.
const WALL_PHYSICS_LAYER_BIT := 1
const WALL_COLLISION_MASK := 1 << WALL_PHYSICS_LAYER_BIT

# Wall-collision mask for an enemy whose active behavior is `behavior`. Normal
# kinds mask the dedicated walls bit so move_and_slide is blocked by wall tiles.
# Behaviors whose `ignores_wall_collision` is true (HauntedSprayBottle floats
# over terrain — issue #165) return 0 so the float contract is preserved. Duck-
# typed on a `get("ignores_wall_collision")` lookup so any future float-kind
# subclass opts in by declaring the flag.
static func wall_mask_for(behavior) -> int:
	if behavior != null and behavior.get("ignores_wall_collision") == true:
		return 0
	return WALL_COLLISION_MASK

# Shared aggro predicate (issue #261). Single source of truth for "this enemy
# is engaged with a player" used by every per-kind ability gate so a freshly-
# loaded level can't be bombarded by off-screen specials. CHASE/ATTACK are
# aggroed; IDLE (out of detection range) and DEAD are not. Duck-typed against
# `enemy.state` so test mocks set an int field — no SceneTree required.
static func is_aggroed(enemy) -> bool:
	if enemy == null:
		return false
	var s = enemy.get("state")
	if s == null:
		return false
	return s == EnemyAIState.State.CHASE or s == EnemyAIState.State.ATTACK

func tick(_delta: float, _enemy) -> void:
	pass

# Idle wander hooks (PRD #391 / tracer slice #392). The IDLE branch of the
# Enemy node calls `idle_velocity(enemy, delta)` each physics frame to drive
# the wander; per-kind subclasses override the trio below to declare their
# style + tuning. Base impl is a no-op (zero velocity) so kinds that haven't
# opted into idle motion yet keep the prior "stand still" behavior.
func idle_style() -> int:
	# Default literal (0 == WanderProfile.Style.STATIONARY_ISH) — avoid a hard
	# class_name ref here so the EnemyBehavior load order stays leaf-free.
	return 0

func idle_speed_fraction() -> float:
	return 0.0

# Idle-velocity template method (PRD #391 / tracer slice #392, deepened out of
# 5x per-kind duplication). Zero unless the enemy is in IDLE state and not mid-
# override (is_overriding_motion() owns motion exclusively, e.g. a dive bomb or
# drunk charge). Subclasses declare tuning via idle_style / idle_speed_fraction
# / idle_radius / idle_change_cadence / idle_pause_length; this base drives the
# shared WanderProfile from that tuning so no per-kind file re-derives it.
func idle_velocity(enemy, delta: float) -> Vector2:
	if enemy == null:
		return Vector2.ZERO
	if is_overriding_motion():
		return Vector2.ZERO
	if enemy.get("state") != EnemyAIState.State.IDLE:
		return Vector2.ZERO
	_ensure_wander_profile(enemy)
	var chase_speed: float = EnemyAIState.CHASE_SPEED
	var ms = enemy.get("move_speed")
	if ms != null:
		chase_speed = float(ms)
	var params := {
		"idle_speed": chase_speed * idle_speed_fraction(),
		"radius": idle_radius(),
		"change_cadence": idle_change_cadence(),
		"pause_length": idle_pause_length(),
	}
	var anchor := _resolve_anchor(enemy)
	var current_pos: Vector2 = Vector2.ZERO
	var gp = enemy.get("global_position")
	if gp != null:
		current_pos = gp
	return _wander_profile.desired_velocity(idle_style(), params, anchor, current_pos, delta)

func _ensure_wander_profile(enemy) -> void:
	if _wander_profile != null:
		return
	var seed_value: int = 0
	var d = enemy.get("data")
	if d != null:
		var eid = d.get("enemy_id")
		if eid != null and str(eid) != "":
			seed_value = hash(eid)
	_wander_profile = WanderProfile.new(seed_value)

func _resolve_anchor(enemy) -> Vector2:
	var d = enemy.get("data")
	if d != null:
		var sp = d.get("spawn_position")
		if sp != null and sp != Vector2.ZERO:
			return sp
	var gp = enemy.get("global_position")
	if gp != null:
		return gp
	return Vector2.ZERO

# Leash radius / phase timing for idle wander (PRD #391). Subclasses override
# to declare their tuning; base defaults keep the no-op contract (zero radius,
# so WanderProfile's leash never engages, matching a kind with no wander).
func idle_radius() -> float:
	return 0.0

func idle_change_cadence() -> float:
	return 1.0

func idle_pause_length() -> float:
	return 0.5

# When a behavior wants to take exclusive control of motion this frame
# (e.g., Angry Pigeon's straight-line dive bomb that must ignore steering),
# it returns true and the Enemy node skips its state-machine match block,
# letting the behavior's tick write global_position / velocity unopposed.
# Default false so the standard chase/attack/idle baseline runs.
func is_overriding_motion() -> bool:
	return false

static func for_kind(kind: int) -> EnemyBehavior:
	match kind:
		EnemyData.EnemyKind.ANGRY_PIGEON:
			return AngryPigeonBehavior.new()
		EnemyData.EnemyKind.ROGUE_ROOMBA:
			return RogueRoombaBehavior.new()
		EnemyData.EnemyKind.DOG_KNIGHT:
			return DogKnightBehavior.new()
		EnemyData.EnemyKind.CATNIP_DEALER:
			return CatnipDealerBehavior.new()
		EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE:
			return HauntedSprayBottleBehavior.new()
	return EnemyBehavior.new()
