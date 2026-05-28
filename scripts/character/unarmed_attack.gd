class_name UnarmedAttack
extends RefCounted

# Unarmed attack controller for PRD #280 / issue #282. When the kitten has
# no weapon equipped, _try_attack routes here instead of the weapon
# AttackChoreographer. The state machine mirrors the choreographer's
# WINDUP → STRIKE → RECOVERY shape so the existing strike-window hitbox
# gating (player.gd::_on_strike_window_open) is reused verbatim — the
# only difference is that no weapon swings; the kitten body itself
# pounces forward for the duration of the burst.
#
# Visual: a directional forward lunge. WINDUP pulls the body slightly back
# (anticipation), STRIKE darts it forward along the attack direction, and
# RECOVERY eases it back to rest. This reads clearly as a paw-swipe/pounce
# and stays distinct from AleEffect's continuous drunken sway.
#
# get_offset() is a pure read of the current body offset; Player sums it
# into _visual.position alongside the ale wobble so the two can coexist
# when an unarmed drunk kitten attacks.

signal hitbox_enable_requested
signal hitbox_disable_requested

enum Phase { IDLE, WINDUP, STRIKE, RECOVERY }

const WINDUP_DURATION := 0.05
const STRIKE_DURATION := 0.06
const RECOVERY_DURATION := 0.11

# Anticipation pull-back, then the forward dart distance (pixels).
const PULLBACK_DISTANCE := 3.0
const LUNGE_DISTANCE := 8.0

var phase: int = Phase.IDLE
var _t: float = 0.0
var _direction := Vector2.RIGHT

func start_attack(direction: Vector2 = Vector2.RIGHT) -> void:
	if phase != Phase.IDLE:
		interrupt()
	if direction != Vector2.ZERO:
		_direction = direction.normalized()
	_t = 0.0
	phase = Phase.WINDUP

func interrupt() -> void:
	var prev := phase
	phase = Phase.IDLE
	_t = 0.0
	if prev == Phase.STRIKE:
		hitbox_disable_requested.emit()

func tick(dt: float) -> void:
	if phase == Phase.IDLE:
		return
	_t += dt
	if phase == Phase.WINDUP and _t >= WINDUP_DURATION:
		_t -= WINDUP_DURATION
		phase = Phase.STRIKE
		hitbox_enable_requested.emit()
	elif phase == Phase.STRIKE and _t >= STRIKE_DURATION:
		_t -= STRIKE_DURATION
		phase = Phase.RECOVERY
		hitbox_disable_requested.emit()
	elif phase == Phase.RECOVERY and _t >= RECOVERY_DURATION:
		_t -= RECOVERY_DURATION
		phase = Phase.IDLE

# Current body offset along the attack direction for the active phase.
# WINDUP: 0 → -PULLBACK. STRIKE: -PULLBACK → +LUNGE. RECOVERY: +LUNGE → 0.
# Zero when idle so the sprite snaps cleanly back to rest between attacks.
func get_offset() -> Vector2:
	match phase:
		Phase.WINDUP:
			var p := clampf(_t / WINDUP_DURATION, 0.0, 1.0)
			return _direction * lerp(0.0, -PULLBACK_DISTANCE, p)
		Phase.STRIKE:
			var p := clampf(_t / STRIKE_DURATION, 0.0, 1.0)
			return _direction * lerp(-PULLBACK_DISTANCE, LUNGE_DISTANCE, p)
		Phase.RECOVERY:
			var p := clampf(_t / RECOVERY_DURATION, 0.0, 1.0)
			return _direction * lerp(LUNGE_DISTANCE, 0.0, p)
		_:
			return Vector2.ZERO

func is_active() -> bool:
	return phase != Phase.IDLE
