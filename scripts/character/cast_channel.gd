class_name CastChannel
extends RefCounted

# Pure cast-channel state (issue #476). Tracks a single in-progress channeled
# cast: start(duration) begins it (or completes instantly for duration <= 0,
# preserving instant-cast spells), tick(dt) advances it, and on_damage_taken()
# cancels it outright — no partial credit, no cooldown, retry is immediate
# since IDLE/CANCELLED both just wait for the next start() call.

enum State { IDLE, ACTIVE, COMPLETE, CANCELLED }

var state: int = State.IDLE
var duration: float = 0.0
var elapsed: float = 0.0

func start(cast_time: float) -> void:
	duration = maxf(0.0, cast_time)
	elapsed = 0.0
	state = State.COMPLETE if duration <= 0.0 else State.ACTIVE

func tick(dt: float) -> void:
	if state != State.ACTIVE or dt <= 0.0:
		return
	elapsed += dt
	if elapsed >= duration:
		state = State.COMPLETE

# Safe no-op when no channel is active (e.g. normal combat damage outside a
# cast). Only ACTIVE channels can be cancelled.
func on_damage_taken() -> void:
	if state != State.ACTIVE:
		return
	state = State.CANCELLED

func is_active() -> bool:
	return state == State.ACTIVE

func is_complete() -> bool:
	return state == State.COMPLETE

func is_cancelled() -> bool:
	return state == State.CANCELLED
