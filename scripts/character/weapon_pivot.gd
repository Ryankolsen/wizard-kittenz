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

enum Phase { IDLE, WINDUP, STRIKE, RECOVERY }

var definition: WeaponDefinition
var phase: int = Phase.IDLE
var _t: float = 0.0
var _dir_sign: float = 1.0

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D")

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
	position = definition.anchor_offset
	if _sprite != null:
		_sprite.position = definition.weapon_offset
	rotation = definition.idle_rotation

# Begin a swing in the given facing direction. Re-swinging mid-animation
# restarts cleanly: the prior phase state is overwritten without an extra
# interrupt call (PRD user story 10).
func swing(direction: Vector2) -> void:
	if definition == null:
		return
	_dir_sign = -1.0 if direction.x < 0.0 else 1.0
	_t = 0.0
	phase = Phase.WINDUP
	rotation = definition.idle_rotation
	if _sprite != null:
		_sprite.position = definition.weapon_offset

# Begin a forward-thrust (CAST/THRUST) in the given facing direction. Shares
# the WINDUP→STRIKE→RECOVERY state machine with swing(); only the per-phase
# animation differs (sprite translation along x, rotation pinned to idle).
func cast(direction: Vector2) -> void:
	if definition == null:
		return
	_dir_sign = -1.0 if direction.x < 0.0 else 1.0
	_t = 0.0
	phase = Phase.WINDUP
	rotation = definition.idle_rotation
	if _sprite != null:
		_sprite.position = definition.weapon_offset

# Abort the active swing immediately and snap back to idle. Used by the
# choreographer when the player attacks again or dies mid-swing.
func interrupt() -> void:
	phase = Phase.IDLE
	_t = 0.0
	if definition != null:
		rotation = definition.idle_rotation
		if _sprite != null:
			_sprite.position = definition.weapon_offset

func tick(dt: float) -> void:
	if phase == Phase.IDLE or definition == null:
		return
	_t += dt
	if definition.attack_type == WeaponDefinition.AttackType.SWING:
		_tick_swing()
	else:
		_tick_thrust()

func _tick_swing() -> void:
	var idle: float = definition.idle_rotation
	var arc: float = definition.swing_arc * _dir_sign
	var windup_rot: float = idle - 0.3 * arc
	var strike_rot: float = idle + arc
	# Loop so a single large dt (e.g. tests passing total_duration in one call)
	# walks the full state machine rather than advancing one boundary at a time.
	while phase != Phase.IDLE:
		if phase == Phase.WINDUP:
			if _t < definition.windup_duration:
				var pw: float = _t / definition.windup_duration
				rotation = lerp(idle, windup_rot, pw)
				return
			_t -= definition.windup_duration
			phase = Phase.STRIKE
		elif phase == Phase.STRIKE:
			if _t < definition.strike_duration:
				var ps: float = _t / definition.strike_duration
				rotation = lerp(windup_rot, strike_rot, ps)
				return
			rotation = strike_rot
			_t -= definition.strike_duration
			phase = Phase.RECOVERY
		elif phase == Phase.RECOVERY:
			if _t < definition.recovery_duration:
				var pr: float = _t / definition.recovery_duration
				rotation = lerp(strike_rot, idle, pr)
				return
			_t = 0.0
			phase = Phase.IDLE
			rotation = idle

# CAST/THRUST animation: rotation stays pinned to idle_rotation; the sprite
# translates forward along the facing direction. Windup pulls slightly back,
# strike thrusts to thrust_distance, recovery returns to the rest offset.
func _tick_thrust() -> void:
	var thrust: float = definition.thrust_distance * _dir_sign
	var rest_offset: Vector2 = definition.weapon_offset
	var windup_offset: Vector2 = rest_offset + Vector2(-0.3 * thrust, 0.0)
	var strike_offset: Vector2 = rest_offset + Vector2(thrust, 0.0)
	rotation = definition.idle_rotation
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
