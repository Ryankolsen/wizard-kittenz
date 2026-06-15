class_name WanderProfile
extends RefCounted

# Pure (RefCounted, no SceneTree) idle-wander module. A function of
#   (style, params, anchor, current_position, delta) -> desired_velocity
# with internal seeded RNG + phase state carrying the wander across ticks.
# Per-mob wander is reproducible from the seed so unit tests and host/client
# simulation are deterministic (PRD #391, tracer slice #392).
#
# STATIONARY_ISH (slice #392) wires the spray bottle's tiny shuffle; PACER
# (slice #393) wires the dog knight's deliberate patrol; RESTLESS (slice #394)
# wires the rogue roomba's near-constant scurry and the angry pigeon's twitchy
# hop. The shared leash applies to every style.

enum Style { STATIONARY_ISH, PACER, RESTLESS }

# Stationary-ish phase mix — mostly pauses with occasional tiny shuffles.
# Picked at the edge of the kind's flavor: ~80% paused, ~20% drifting.
const _STATIONARY_PAUSE_CHANCE: float = 0.8

# Restless rarely pauses — ~5% of phase transitions go to a brief pause and
# the other ~95% re-roll a fresh moving heading. Combined with a short
# change_cadence, the path reads as near-constant twitchy motion.
const _RESTLESS_PAUSE_CHANCE: float = 0.05

var _rng: RandomNumberGenerator
var _heading: Vector2 = Vector2.ZERO
var _is_paused: bool = true
var _phase_time_left: float = 0.0

func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

# Per-tick desired velocity for the given style + tuning. `params` keys:
#   idle_speed: float (px/s, the styled speed; typically chase_speed * fraction)
#   radius: float (anchor leash radius — beyond this, velocity pulls inward)
#   change_cadence: float (seconds a drift heading holds before re-rolling)
#   pause_length: float (seconds a pause holds before re-rolling)
func desired_velocity(style: int, params: Dictionary, anchor: Vector2,
		current_pos: Vector2, delta: float) -> Vector2:
	var idle_speed: float = float(params.get("idle_speed", 0.0))
	var radius: float = float(params.get("radius", 0.0))
	var change_cadence: float = float(params.get("change_cadence", 1.0))
	var pause_length: float = float(params.get("pause_length", 0.5))
	_phase_time_left -= delta
	if _phase_time_left <= 0.0:
		_advance_phase(style, change_cadence, pause_length)
	var velocity: Vector2 = Vector2.ZERO if _is_paused else _heading * idle_speed
	# Leash: at/past the anchor radius, override with a pull back toward
	# anchor so wanderers can't drift out of their tether. Drives the
	# "never exceeds radius" property the tests assert.
	if radius > 0.0:
		var offset := current_pos - anchor
		if offset.length() >= radius:
			velocity = -offset.normalized() * idle_speed
	return velocity

func _advance_phase(style: int, change_cadence: float, pause_length: float) -> void:
	match style:
		Style.STATIONARY_ISH:
			if _rng.randf() < _STATIONARY_PAUSE_CHANCE:
				_is_paused = true
				_heading = Vector2.ZERO
				_phase_time_left = pause_length
			else:
				_is_paused = false
				var theta := _rng.randf() * TAU
				_heading = Vector2(cos(theta), sin(theta))
				_phase_time_left = change_cadence
		Style.PACER:
			# Deterministic move/pause alternation — "patrolling its post". Each
			# move phase re-rolls a fresh heading so the patrol path isn't a
			# single line back-and-forth. Dog knight wires this in (slice #393).
			if _is_paused:
				_is_paused = false
				var theta := _rng.randf() * TAU
				_heading = Vector2(cos(theta), sin(theta))
				_phase_time_left = change_cadence
			else:
				_is_paused = true
				_heading = Vector2.ZERO
				_phase_time_left = pause_length
		Style.RESTLESS:
			# Near-constant motion: most phase transitions re-roll a fresh moving
			# heading; only a small chance flips to a brief pause. Wired to rogue
			# roomba (most active) and angry pigeon (twitchy) in slice #394.
			if _rng.randf() < _RESTLESS_PAUSE_CHANCE:
				_is_paused = true
				_heading = Vector2.ZERO
				_phase_time_left = pause_length
			else:
				_is_paused = false
				var theta := _rng.randf() * TAU
				_heading = Vector2(cos(theta), sin(theta))
				_phase_time_left = change_cadence
		_:
			# Unknown style — fall through to a paused phase so unmapped styles
			# don't crash.
			_is_paused = true
			_heading = Vector2.ZERO
			_phase_time_left = pause_length
