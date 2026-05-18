class_name HealSyncOutboundBridge
extends RefCounted

const HealBroadcasterRef = preload("res://scripts/networking/heal_broadcaster.gd")

# Outbound co-op HEAL bridge: subscribes to a HealBroadcasterRef's
# heal_applied signal and routes each event through NakamaLobby
# .send_heal_async. Closes the last remaining gap in the cross-client
# Sleepy Kitten heal/buff loop (PRD #140, follow-up to slice #146):
# the inbound wire + applier are already in place, and the local-cast
# emit on session.heal_broadcaster is wired by SpellEffectResolver
# once Player threads the broadcaster in; this module is the final hop
# that puts the (target_id, effect_kind, amount, duration) tuple on
# the wire.
#
# Sibling-shaped to TauntSyncOutboundBridge — same bind/unbind contract,
# same rebind-replaces-old invariant, same caster_id-dropped-on-wire
# anti-spoof model (Nakama tags every packet with the sender presence,
# so the receiver reads caster_id off the socket envelope).

var _broadcaster: HealBroadcasterRef = null
# Loosely typed so tests can pass a stub with just `send_heal_async`
# without needing a live socket. Production callers always pass a
# NakamaLobby.
var _lobby = null

func _init(broadcaster: HealBroadcasterRef = null, lobby = null) -> void:
	if broadcaster != null and lobby != null:
		bind(broadcaster, lobby)

# Connects to the broadcaster's heal_applied signal. Returns true on
# a fresh bind, false on null inputs or an already-bound-to-same
# broadcaster no-op. Re-binding to a *different* broadcaster
# transparently unbinds the old one first so the bridge can be reused
# across runs without the caller having to remember the unbind step.
func bind(broadcaster: HealBroadcasterRef, lobby) -> bool:
	if broadcaster == null or lobby == null:
		return false
	if _broadcaster == broadcaster:
		return false
	if _broadcaster != null:
		unbind()
	_broadcaster = broadcaster
	_lobby = lobby
	_broadcaster.heal_applied.connect(_on_heal_applied)
	return true

# Disconnects from the bound broadcaster and clears the routing state.
# Returns true on a successful unbind, false on no-op (not currently
# bound). Called by CoopSession._drop_managers on session end so a
# dropped bridge doesn't keep firing send_heal_async after the run.
func unbind() -> bool:
	if _broadcaster == null:
		return false
	if _broadcaster.heal_applied.is_connected(_on_heal_applied):
		_broadcaster.heal_applied.disconnect(_on_heal_applied)
	_broadcaster = null
	_lobby = null
	return true

func is_bound() -> bool:
	return _broadcaster != null

func _on_heal_applied(_caster_id: String, target_id: String, effect_kind: String, amount: int, duration: float) -> void:
	if _lobby == null:
		return
	_lobby.send_heal_async(target_id, effect_kind, amount, duration)
