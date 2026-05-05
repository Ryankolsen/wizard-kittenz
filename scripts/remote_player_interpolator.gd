class_name RemotePlayerInterpolator
extends RefCounted

# Smooths a remote kitten's position between network snapshots so the
# rendered movement doesn't teleport every time a packet lands. Two-slot
# buffer (previous, current) — push_sample shifts current into previous
# and stores the new state; get_display_position lerps between them given
# t in [0,1].
#
# This is the rendering-side companion to NetworkSyncManager: the manager
# owns one interpolator per remote player_id and forwards apply_remote_state
# calls into push_sample. The render loop calls get_display_position with
# t = (now - prev_ts) / (curr_ts - prev_ts) clamped to [0,1].
#
# Before any sample lands, get_display_position returns Vector2.ZERO so the
# remote kitten doesn't render at a stale origin. After exactly one sample
# (no previous to lerp from), it returns current_position — the kitten
# pops in at the first known location instead of crawling out of (0, 0).
var previous_position: Vector2 = Vector2.ZERO
var current_position: Vector2 = Vector2.ZERO
var previous_timestamp: float = 0.0
var current_timestamp: float = 0.0
var _has_previous: bool = false
var _has_current: bool = false

func push_sample(position: Vector2, timestamp: float = 0.0) -> void:
	if _has_current:
		previous_position = current_position
		previous_timestamp = current_timestamp
		_has_previous = true
	current_position = position
	current_timestamp = timestamp
	_has_current = true

func get_display_position(t: float) -> Vector2:
	if not _has_current:
		return Vector2.ZERO
	if not _has_previous:
		return current_position
	var clamped_t: float = clampf(t, 0.0, 1.0)
	return previous_position.lerp(current_position, clamped_t)

func has_sample() -> bool:
	return _has_current

func sample_count() -> int:
	if _has_previous:
		return 2
	if _has_current:
		return 1
	return 0
