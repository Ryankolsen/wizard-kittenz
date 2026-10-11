class_name ReconnectCoordinator
extends RefCounted

# Pure, externally-time-driven retry/backoff decision machine for reconnect
# attempts (#636/#638). Owns ONLY the "when is a reconnect attempt allowed,
# and did the cycle succeed or run out of road" logic — zero knowledge of
# sockets, Nakama, or the scene tree. Sibling-shaped to PositionBroadcastGate:
# every call takes a caller-supplied `now: float` (seconds), there is no
# internal Timer and no _process, which is what makes this deterministically
# unit-testable without ever sleeping a real clock.
#
# What this does NOT do:
#   - Open a socket, call Nakama, or retry anything itself. The wire layer
#     (#639/#640) polls ready_for_next_attempt(now), does its own real
#     reconnect attempt when it returns true, and reports the outcome via
#     note_attempt_result. This class never initiates I/O.
#   - Render any UI. That's #641 (not in this run) — it would subscribe to
#     this class's signals / poll state() to drive a reconnect banner.
#
# Lifecycle:
#   IDLE -> RETRYING (via start) -> SUCCEEDED | EXHAUSTED (terminal)
#   A terminated instance must go through reset() -> IDLE before a later,
#   unrelated drop in the same match can start a new cycle. This mirrors
#   PositionBroadcastGate.reset() (reusable instance) rather than requiring
#   callers to throw the object away and reconstruct it.

signal reconnect_started
signal reconnect_succeeded
signal reconnect_exhausted

enum State { IDLE, RETRYING, SUCCEEDED, EXHAUSTED }

const DEFAULT_RETRY_INTERVAL_SECONDS: float = 5.0
const DEFAULT_RETRY_WINDOW_SECONDS: float = 45.0

var retry_interval_seconds: float = DEFAULT_RETRY_INTERVAL_SECONDS
var retry_window_seconds: float = DEFAULT_RETRY_WINDOW_SECONDS

var _state: int = State.IDLE
var _cycle_start_time: float = 0.0
var _last_attempt_time: float = 0.0
var _has_attempted: bool = false

func _init(
	interval: float = DEFAULT_RETRY_INTERVAL_SECONDS,
	window: float = DEFAULT_RETRY_WINDOW_SECONDS,
) -> void:
	retry_interval_seconds = interval
	retry_window_seconds = window

func state() -> int:
	return _state

# Begins a retry cycle. Edge-gated like HostPauseState.set_paused: calling
# start() again while already RETRYING is a no-op — it must NOT reset
# _cycle_start_time, since that would silently grant extra retry window to
# a caller that (mistakenly, or on a duplicate wire event) calls start()
# mid-cycle. Only a fresh cycle from IDLE gets a new baseline.
func start(now: float) -> void:
	if _state == State.RETRYING:
		return
	_state = State.RETRYING
	_cycle_start_time = now
	_has_attempted = false
	reconnect_started.emit()

# Predicate the caller polls before firing a real reconnect attempt.
#
# Returns true at most once per retry_interval_seconds while RETRYING, and
# always true on the very first call after start() (no forced initial wait —
# the player shouldn't sit through a full interval before the first attempt
# even gets to happen). Returns false once the cycle has terminated
# (SUCCEEDED/EXHAUSTED/IDLE) or the total retry window has elapsed.
#
# Note: this does NOT itself transition to EXHAUSTED on window expiry — that
# transition only happens via note_attempt_result's failure path or cancel(),
# so the state machine's terminal transitions are always tied to an actual
# reported attempt outcome (or an explicit cancel), never silently inferred
# from a polling call that might be invoked at an arbitrary cadence.
func ready_for_next_attempt(now: float) -> bool:
	if _state != State.RETRYING:
		return false
	if now - _cycle_start_time >= retry_window_seconds:
		return false
	if not _has_attempted:
		_has_attempted = true
		_last_attempt_time = now
		return true
	if now - _last_attempt_time < retry_interval_seconds:
		return false
	_last_attempt_time = now
	return true

# Caller reports the outcome of an attempt it was told to make via
# ready_for_next_attempt. Success always wins and ends the cycle immediately,
# regardless of how many prior failures there were. Failure only terminates
# the cycle (EXHAUSTED) once the total window has elapsed since start();
# otherwise the cycle stays RETRYING so a later ready_for_next_attempt call
# can fire again.
func note_attempt_result(now: float, success: bool) -> void:
	if _state != State.RETRYING:
		return
	if success:
		_state = State.SUCCEEDED
		reconnect_succeeded.emit()
		return
	if now - _cycle_start_time >= retry_window_seconds:
		_state = State.EXHAUSTED
		reconnect_exhausted.emit()

# Caller-initiated abort (e.g. player taps "give up"). Forces EXHAUSTED
# immediately regardless of elapsed time or remaining window. Edge-gated so
# cancel() from IDLE/SUCCEEDED/already-EXHAUSTED is a no-op — only a live
# RETRYING cycle can be cancelled, matching HostPauseState.set_paused's
# "only fire on a real transition" contract.
func cancel() -> void:
	if _state != State.RETRYING:
		return
	_state = State.EXHAUSTED
	reconnect_exhausted.emit()

# Returns to IDLE regardless of current state, with no signal emitted, so
# the same instance can be reused for a later, unrelated drop in the same
# match. No signal fires here deliberately: reset() is bookkeeping between
# cycles, not a state transition callers should react to.
func reset() -> void:
	_state = State.IDLE
	_cycle_start_time = 0.0
	_last_attempt_time = 0.0
	_has_attempted = false
