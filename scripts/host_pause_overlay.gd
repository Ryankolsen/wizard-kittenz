class_name HostPauseOverlay
extends CanvasLayer

# Non-host overlay shown when the host pauses the party (#43, PRD #42).
# Listens to the active NakamaLobby's host_paused / host_unpaused signals
# through GameState and toggles its own visibility. The host sees their
# own PauseMenu's "Unpause for everyone" toggle instead, so this overlay
# is suppressed for the host (lobby.is_local_host() == true).
#
# process_mode = PROCESS_MODE_ALWAYS so visibility-toggle still runs while
# get_tree().paused is true (every client's tree is paused via the bridge
# in GameState._on_host_paused during a host-pause). Without ALWAYS the
# overlay would freeze along with the rest of the scene and could never
# render itself onto the screen the player is staring at.
#
# Non-dismissable by spec: no buttons, no input handling — the only way
# out is the host releasing the pause (or disconnecting, which triggers
# the auto-release in NakamaLobby.apply_leaves).

var _bound_lobby: NakamaLobby = null

func _ready() -> void:
	visible = false
	_bind_to_current_lobby()

# Connects to the currently-set GameState.lobby's host-pause signals.
# Called from _ready and re-callable so a future "lobby replaced mid-
# dungeon" path (rejoin / reconnect) could call this to rebind. Defensive
# disconnect of the prior lobby keeps a stale binding from leaking pause
# flips into the next session.
func _bind_to_current_lobby() -> void:
	if _bound_lobby != null:
		if _bound_lobby.host_paused.is_connected(_on_host_paused):
			_bound_lobby.host_paused.disconnect(_on_host_paused)
		if _bound_lobby.host_unpaused.is_connected(_on_host_unpaused):
			_bound_lobby.host_unpaused.disconnect(_on_host_unpaused)
		_bound_lobby = null
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var lobby: NakamaLobby = gs.lobby
	if lobby == null:
		return
	_bound_lobby = lobby
	lobby.host_paused.connect(_on_host_paused)
	lobby.host_unpaused.connect(_on_host_unpaused)

func _on_host_paused() -> void:
	# Suppress on the host's own client — the host has their pause menu's
	# Unpause toggle as the surface to interact with. The overlay is for
	# non-host players who otherwise have no UI feedback explaining why
	# their inputs are frozen.
	if _bound_lobby != null and _bound_lobby.is_local_host():
		return
	visible = true

func _on_host_unpaused() -> void:
	visible = false
