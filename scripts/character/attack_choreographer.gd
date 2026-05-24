class_name AttackChoreographer
extends RefCounted

# Phase orchestrator for the player attack pivot system (PRD #223). Drives
# the windup → strike → recovery state machine using durations from the
# active WeaponDefinition, forwards ticks into the bound WeaponPivot, and
# emits signals at phase boundaries so callers can gate hitbox / VFX / SFX
# without coupling those concerns into this module.
#
# Slice 1 wires the SWING type for the battle kitten only. THRUST and CAST
# branch off start_attack(...) in slices 2 and 3 but reuse this same state
# machine — only the visual the WeaponPivot performs differs.

signal phase_entered(phase: int)
signal hitbox_enable_requested
signal hitbox_disable_requested
signal strike_vfx_requested(direction: Vector2)

enum Phase { IDLE, WINDUP, STRIKE, RECOVERY }

var definition: WeaponDefinition
var weapon_pivot: WeaponPivot = null
var phase: int = Phase.IDLE
var _t: float = 0.0
var _direction: Vector2 = Vector2.RIGHT

func start_attack(direction: Vector2, attack_type: int = WeaponDefinition.AttackType.SWING) -> void:
	if definition == null:
		return
	# PRD #223 / issue #228: rapid re-attacks must clean-interrupt the in-flight
	# sequence before restarting. Without this, a mid-STRIKE re-attack would
	# bypass hitbox_disable_requested (start_attack jumps phase straight to
	# WINDUP) and leave the damage window stuck "on" until the next strike's
	# natural close — observable as double-damage chains on attack-spam.
	if phase != Phase.IDLE:
		interrupt()
	_direction = direction
	_t = 0.0
	if weapon_pivot != null:
		match attack_type:
			WeaponDefinition.AttackType.CAST, WeaponDefinition.AttackType.THRUST:
				weapon_pivot.cast(direction)
			_:
				weapon_pivot.swing(direction)
	_enter_phase(Phase.WINDUP)

func interrupt() -> void:
	var prev := phase
	phase = Phase.IDLE
	_t = 0.0
	if prev == Phase.STRIKE:
		hitbox_disable_requested.emit()
	if weapon_pivot != null:
		weapon_pivot.interrupt()

func tick(dt: float) -> void:
	if phase == Phase.IDLE or definition == null:
		return
	_t += dt
	if weapon_pivot != null:
		weapon_pivot.tick(dt)
	if phase == Phase.WINDUP and _t >= definition.windup_duration:
		_t -= definition.windup_duration
		_enter_phase(Phase.STRIKE)
	elif phase == Phase.STRIKE and _t >= definition.strike_duration:
		_t -= definition.strike_duration
		_enter_phase(Phase.RECOVERY)
	elif phase == Phase.RECOVERY and _t >= definition.recovery_duration:
		_t -= definition.recovery_duration
		_enter_phase(Phase.IDLE)

func _enter_phase(p: int) -> void:
	var prev := phase
	phase = p
	phase_entered.emit(p)
	if p == Phase.STRIKE:
		hitbox_enable_requested.emit()
		strike_vfx_requested.emit(_direction)
	elif p == Phase.RECOVERY and prev == Phase.STRIKE:
		hitbox_disable_requested.emit()
	elif p == Phase.IDLE and prev == Phase.STRIKE:
		# Defensive — STRIKE always transitions through RECOVERY in tick(),
		# but interrupt() routes can collapse the order; ensure the hitbox
		# never sticks open.
		hitbox_disable_requested.emit()
