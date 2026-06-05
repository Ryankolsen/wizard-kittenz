class_name RemotePlayerInterpolator
extends RefCounted

# Smooths a remote kitten's position between network snapshots so the
# rendered movement doesn't teleport every time a packet lands.
#
# Bug background (PRD #338): the previous implementation stamped each
# sample with the *sender's* wire timestamp and lerped against the
# receiver's render clock. The two clocks come from different processes
# (Time.get_ticks_msec since each app's launch) with no shared origin,
# so the lerp window was effectively undefined — `t` jittered all over
# [0,1] across the render loop, producing the choppy / freezing remote
# kitten the PRD describes.
#
# Fix: stamp every sample with the *receiver's* local clock at arrival
# (caller-injected via push_sample's `arrival_time`), buffer a small
# bounded ring of samples, and render at `target = now - INTERPOLATION_DELAY`
# — a fixed render-behind offset. The interpolator finds the two
# buffered samples whose arrival times bracket `target` and lerps
# between them, giving a stable lerp window driven entirely by one
# clock. INTERPOLATION_DELAY trades a tiny bit of visible latency for
# smoothness when packets jitter inside the window.
#
# Edge policy:
#   - 0 samples: Vector2.ZERO (kitten stays off-screen pre-first-packet).
#   - 1 sample: that sample's position (pop in at first known location).
#   - target newer than newest arrival: clamp to newest (freeze in place
#     while stalled; no extrapolation).
#   - target older than oldest retained: clamp to oldest (just-bound
#     defensive case; in steady state INTERPOLATION_DELAY keeps target
#     comfortably inside the buffered window).
#
# The interpolator reads no clock of its own — both `arrival_time` and
# `now` are caller-injected, preserving unit-testability without a real
# scene tree or Time autoload mock.

const BUFFER_CAPACITY: int = 4
const INTERPOLATION_DELAY: float = 0.15

# Oldest-first list of {position: Vector2, arrival_time: float} entries.
# Cap at BUFFER_CAPACITY; oldest is evicted on overflow. Because callers
# stamp arrival_time with their own monotonic clock, the buffer is
# monotonic by construction — no reordering logic required.
var _samples: Array = []

func push_sample(position: Vector2, arrival_time: float = 0.0) -> void:
	_samples.append({"position": position, "arrival_time": arrival_time})
	if _samples.size() > BUFFER_CAPACITY:
		_samples.pop_front()

func get_display_position_at(now: float) -> Vector2:
	var n: int = _samples.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return _samples[0]["position"]
	var target: float = now - INTERPOLATION_DELAY
	var newest: Dictionary = _samples[n - 1]
	if target >= newest["arrival_time"]:
		return newest["position"]
	var oldest: Dictionary = _samples[0]
	if target <= oldest["arrival_time"]:
		return oldest["position"]
	for i in range(n - 1):
		var a: Dictionary = _samples[i]
		var b: Dictionary = _samples[i + 1]
		var a_t: float = a["arrival_time"]
		var b_t: float = b["arrival_time"]
		if a_t <= target and target <= b_t:
			var window: float = b_t - a_t
			if window <= 0.0:
				return b["position"]
			var t: float = (target - a_t) / window
			return (a["position"] as Vector2).lerp(b["position"], t)
	return newest["position"]

func has_sample() -> bool:
	return _samples.size() > 0

func sample_count() -> int:
	return _samples.size()

# Test-only accessor for the newest sample's position. Production code
# always goes through get_display_position_at; this exists so tests can
# assert "the latest pushed sample is what we expect" without leaking
# the internal _samples array shape.
func newest_position() -> Vector2:
	if _samples.is_empty():
		return Vector2.ZERO
	return _samples[_samples.size() - 1]["position"]
