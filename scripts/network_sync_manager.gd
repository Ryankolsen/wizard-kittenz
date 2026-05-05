class_name NetworkSyncManager
extends RefCounted

# Per-remote-player interpolation registry. The wire layer (Nakama after
# #14 lands) calls apply_remote_state with the wire payload's player_id,
# position, and timestamp; the render loop reads back via
# get_display_position(player_id, t) to draw the smoothed kitten.
#
# A first apply_remote_state for an unknown player_id auto-registers a
# fresh RemotePlayerInterpolator — the UI doesn't have to call a separate
# "register player" hook, because the lobby roster (#16) is already the
# source of truth for who's connected; the manager just lazily mints an
# interpolator when the first state packet arrives.
#
# Drop a player by player_id when the lobby fires "player left" so a
# disconnected kitten stops occupying interpolation state.
var _interpolators: Dictionary = {}  # player_id -> RemotePlayerInterpolator

# Updates the remote player's interpolation target. Auto-registers the
# player on first call. Returns the interpolator so the caller can chain
# (e.g. read sample_count() without a second lookup).
func apply_remote_state(player_id: String, position: Vector2, timestamp: float = 0.0) -> RemotePlayerInterpolator:
	if player_id == "":
		return null
	var interp: RemotePlayerInterpolator = _interpolators.get(player_id)
	if interp == null:
		interp = RemotePlayerInterpolator.new()
		_interpolators[player_id] = interp
	interp.push_sample(position, timestamp)
	return interp

func get_display_position(player_id: String, t: float) -> Vector2:
	var interp: RemotePlayerInterpolator = _interpolators.get(player_id)
	if interp == null:
		return Vector2.ZERO
	return interp.get_display_position(t)

# Wall-clock variant. Forwards to RemotePlayerInterpolator.get_display_position_at
# so the render loop / wire layer can call a single one-liner per remote
# player_id each frame instead of looking up the interpolator and computing
# t inline. Unknown player_id returns Vector2.ZERO (same shape as
# get_display_position) so a wire packet for a player who already left the
# lobby doesn't crash the render path.
func get_display_position_at(player_id: String, now: float) -> Vector2:
	var interp: RemotePlayerInterpolator = _interpolators.get(player_id)
	if interp == null:
		return Vector2.ZERO
	return interp.get_display_position_at(now)

func get_interpolator(player_id: String) -> RemotePlayerInterpolator:
	return _interpolators.get(player_id)

func has_player(player_id: String) -> bool:
	return _interpolators.has(player_id)

func remove_player(player_id: String) -> bool:
	return _interpolators.erase(player_id)

func player_count() -> int:
	return _interpolators.size()

func clear() -> void:
	_interpolators.clear()
