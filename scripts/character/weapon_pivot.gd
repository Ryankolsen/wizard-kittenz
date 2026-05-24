class_name WeaponPivot
extends Node2D

# Pure-visual weapon animator. Owns a child Sprite2D textured from
# WeaponDefinition.texture_path. Knows nothing about damage, input, or
# networking — AttackChoreographer drives phase transitions; WeaponPivot
# just interpolates rotation across the windup → strike → recovery span
# of the active swing.
#
# Tick-based (not Tween-based) so tests can advance time deterministically
# without awaiting timers. _process forwards real delta into tick(dt) so
# the in-game path animates frame-by-frame.
#
# Facing model (do NOT set scale.x = -1 on the pivot itself): Godot's
# Transform2D applies scale BEFORE rotation, so flipping pivot.scale.x
# also inverts the rotation's y-component — making a downward chop read
# as an upward chop when facing left. Instead we mirror the pivot's own
# position.x, mirror the sprite's local position.x, mirror the sprite's
# pixels via sprite.scale.x = _facing, and negate all rotation values
# (idle / windup / strike) by _facing. That keeps the chop pointing down
# on both sides while still presenting the weapon on the correct flank.

enum Phase { IDLE, WINDUP, STRIKE, RECOVERY }

var definition: WeaponDefinition
var phase: int = Phase.IDLE
var _t: float = 0.0
# Visual facing of the pivot. Drives position mirroring, sprite pixel
# flipping, and rotation-sign negation in the swing/cast math.
var _facing: float = 1.0

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D")

# Mirror the weapon's resting side based on the kitten's facing. Zero is a
# no-op (idle / stationary) so callers can route input_dir.x through here
# without an extra branch.
func set_facing(facing_x: float) -> void:
	if facing_x > 0.0:
		_facing = 1.0
	elif facing_x < 0.0:
		_facing = -1.0
	# else: keep prior facing
	_apply_facing_to_idle_pose()

func _ready() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D")
	if definition != null:
		_apply_definition()

func set_definition(d: WeaponDefinition) -> void:
	definition = d
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D")
	_apply_definition()

func _apply_definition() -> void:
	if definition == null:
		return
	if _sprite != null and definition.texture_path != "":
		var tex := load(definition.texture_path)
		if tex != null:
			_sprite.texture = tex
	if _sprite != null:
		_sprite.scale = definition.sprite_scale
	_apply_facing_to_idle_pose()

# Snap the pivot + sprite back to the resting pose for the current facing.
# Reused by set_facing, _apply_definition, and interrupt — anywhere we need
# the weapon to read as "at rest, ready to swing" without an active phase.
func _apply_facing_to_idle_pose() -> void:
	if definition == null:
		return
	position = Vector2(definition.anchor_offset.x * _facing, definition.anchor_offset.y)
	rotation = definition.idle_rotation * _facing
	if _sprite != null:
		_sprite.position = Vector2(definition.weapon_offset.x * _facing, definition.weapon_offset.y)
		# Preserve sprite_scale.y (used by chonk mug for proportional sizing)
		# while flipping x by _facing for pixel-mirroring.
		_sprite.scale = Vector2(definition.sprite_scale.x * _facing, definition.sprite_scale.y)

# Begin a swing in the given facing direction. Re-swinging mid-animation
# restarts cleanly: the prior phase state is overwritten without an extra
# interrupt call (PRD user story 10).
func swing(direction: Vector2) -> void:
	if definition == null:
		return
	set_facing(direction.x)
	_t = 0.0
	phase = Phase.WINDUP

# Begin a forward-thrust (CAST/THRUST) in the given facing direction. Shares
# the WINDUP→STRIKE→RECOVERY state machine with swing(); only the per-phase
# animation differs (sprite translation along x, rotation pinned to idle).
func cast(direction: Vector2) -> void:
	if definition == null:
		return
	set_facing(direction.x)
	_t = 0.0
	phase = Phase.WINDUP

# Abort the active swing immediately and snap back to idle. Used by the
# choreographer when the player attacks again or dies mid-swing.
func interrupt() -> void:
	phase = Phase.IDLE
	_t = 0.0
	_apply_facing_to_idle_pose()

func tick(dt: float) -> void:
	if phase == Phase.IDLE or definition == null:
		return
	_t += dt
	if definition.attack_type == WeaponDefinition.AttackType.SWING:
		_tick_swing()
	else:
		_tick_thrust()

func _tick_swing() -> void:
	# All rotation values are computed in the right-facing frame and then
	# multiplied by _facing. That makes the swing arc symmetric across the
	# y-axis without re-deriving each phase boundary by hand.
	var idle: float = definition.idle_rotation
	var arc: float = definition.swing_arc
	var windup_rot: float = idle - 0.3 * arc
	var strike_rot: float = idle + arc
	# Loop so a single large dt (e.g. tests passing total_duration in one call)
	# walks the full state machine rather than advancing one boundary at a time.
	while phase != Phase.IDLE:
		if phase == Phase.WINDUP:
			if _t < definition.windup_duration:
				var pw: float = _t / definition.windup_duration
				rotation = lerp(idle, windup_rot, pw) * _facing
				return
			_t -= definition.windup_duration
			phase = Phase.STRIKE
		elif phase == Phase.STRIKE:
			if _t < definition.strike_duration:
				var ps: float = _t / definition.strike_duration
				rotation = lerp(windup_rot, strike_rot, ps) * _facing
				return
			rotation = strike_rot * _facing
			_t -= definition.strike_duration
			phase = Phase.RECOVERY
		elif phase == Phase.RECOVERY:
			if _t < definition.recovery_duration:
				var pr: float = _t / definition.recovery_duration
				rotation = lerp(strike_rot, idle, pr) * _facing
				return
			_t = 0.0
			phase = Phase.IDLE
			rotation = idle * _facing

# CAST/THRUST animation: rotation stays pinned to idle_rotation (mirrored
# by _facing); the sprite translates forward along the facing direction.
# Windup pulls slightly back, strike thrusts to thrust_distance, recovery
# returns to the rest offset. All x-offsets are multiplied by _facing so
# the thrust extends outward in the kitten's facing direction.
func _tick_thrust() -> void:
	var thrust: float = definition.thrust_distance
	var rest_offset := Vector2(definition.weapon_offset.x * _facing, definition.weapon_offset.y)
	var windup_offset: Vector2 = rest_offset + Vector2(-0.3 * thrust * _facing, 0.0)
	var strike_offset: Vector2 = rest_offset + Vector2(thrust * _facing, 0.0)
	rotation = definition.idle_rotation * _facing
	while phase != Phase.IDLE:
		if phase == Phase.WINDUP:
			if _t < definition.windup_duration:
				var pw: float = _t / definition.windup_duration
				if _sprite != null:
					_sprite.position = rest_offset.lerp(windup_offset, pw)
				return
			_t -= definition.windup_duration
			phase = Phase.STRIKE
		elif phase == Phase.STRIKE:
			if _t < definition.strike_duration:
				var ps: float = _t / definition.strike_duration
				if _sprite != null:
					_sprite.position = windup_offset.lerp(strike_offset, ps)
				return
			if _sprite != null:
				_sprite.position = strike_offset
			_t -= definition.strike_duration
			phase = Phase.RECOVERY
		elif phase == Phase.RECOVERY:
			if _t < definition.recovery_duration:
				var pr: float = _t / definition.recovery_duration
				if _sprite != null:
					_sprite.position = strike_offset.lerp(rest_offset, pr)
				return
			_t = 0.0
			phase = Phase.IDLE
			if _sprite != null:
				_sprite.position = rest_offset

func _process(delta: float) -> void:
	tick(delta)
