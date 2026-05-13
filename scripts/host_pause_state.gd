class_name HostPauseState
extends RefCounted

# Per-match host-initiated pause state. Pure data — no scene tree, no Nakama.
# Owned by NakamaLobby (lifetime matches the lobby instance). When the wire
# layer receives OP_HOST_PAUSE / OP_HOST_UNPAUSE it mutates this and emits
# host_paused / host_unpaused so the scene-tree side (a future overlay scene
# + get_tree().paused = true bridge in GameState) can react without poking
# at lobby internals.
#
# Distinct from the per-player soft-pause in #42 (PauseMenu). The PauseMenu
# only overlays the local player's screen while the game continues for
# everyone else; HostPauseState freezes all clients simultaneously and only
# the host (lobby creator) can trigger or release it.

var _paused: bool = false

func is_paused() -> bool:
	return _paused

# Sets the pause state. Returns true when the value actually changed (rising
# or falling edge) so callers can gate signal emission / overlay-toggle on a
# real transition and not re-fire on duplicate packets from the wire.
func set_paused(value: bool) -> bool:
	if _paused == value:
		return false
	_paused = value
	return true

# Drops state without ceremony. Called from NakamaLobby.leave_async and on
# host-disconnect auto-release so the next match starts in a known-unpaused
# state.
func clear() -> void:
	_paused = false
