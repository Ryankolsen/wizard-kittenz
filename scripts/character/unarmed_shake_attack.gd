class_name UnarmedShakeAttack
extends RefCounted

# Unarmed attack controller for PRD #280 / issue #282. When the kitten has
# no weapon equipped, _try_attack routes here instead of the weapon
# AttackChoreographer. The state machine mirrors the choreographer's
# WINDUP → STRIKE → RECOVERY shape so the existing strike-window hitbox
# gating (player.gd::_on_strike_window_open) is reused verbatim — the
# only difference is that no weapon swings; the kitten body itself
# shudders for the duration of the burst.
#
# Visual: a short high-frequency square-wave oscillation on the visual
# offset, intentionally NOT a smooth sinusoid. This is what makes the
# unarmed shake read differently from AleEffect's drunken sway, which
# is a continuous low-frequency sine while the buff is active. Here the
# burst is bounded to ~0.22s per attack and oscillates fast enough to
# read as a vibrate.
#
# get_offset() is a pure read of the current shake offset; Player sums
# it into _visual.position alongside the ale wobble so the two effects
# can coexist when an unarmed drunk kitten swings.

signal hitbox_enable_requested
signal hitbox_disable_requested

enum Phase { IDLE, WINDUP, STRIKE, RECOVERY }

const WINDUP_DURATION := 0.05
const STRIKE_DURATION := 0.06
const RECOVERY_DURATION := 0.11

const SHAKE_AMPLITUDE := 2.5
const SHAKE_FREQUENCY := 32.0

var phase: int = Phase.IDLE
var _t: float = 0.0
var _elapsed: float = 0.0

func start_attack() -> void:
	if phase != Phase.IDLE:
		interrupt()
	_t = 0.0
	_elapsed = 0.0
	phase = Phase.WINDUP

func interrupt() -> void:
	var prev := phase
	phase = Phase.IDLE
	_t = 0.0
	_elapsed = 0.0
	if prev == Phase.STRIKE:
		hitbox_disable_requested.emit()

func tick(dt: float) -> void:
	if phase == Phase.IDLE:
		return
	_t += dt
	_elapsed += dt
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
		_elapsed = 0.0

# Current visual offset to apply to the body sprite. Square-wave on a
# horizontal axis — flips sign at SHAKE_FREQUENCY Hz, giving a distinct
# vibrate rather than the smooth sway of AleEffect. Zero when idle so
# the sprite snaps cleanly back to rest between attacks.
func get_offset() -> Vector2:
	if phase == Phase.IDLE:
		return Vector2.ZERO
	var sign_x := 1.0 if int(_elapsed * SHAKE_FREQUENCY) % 2 == 0 else -1.0
	return Vector2(sign_x * SHAKE_AMPLITUDE, 0.0)

func is_active() -> bool:
	return phase != Phase.IDLE
