class_name TauntSyncOutboundBridge
extends RefCounted

# Outbound co-op TAUNT bridge: subscribes to a TauntBroadcaster's
# taunt_applied signal and routes each event through NakamaLobby
# .send_taunt_async. Closes the last remaining gap in the cross-client
# TAUNT loop (PRD #124, follow-up to e1b7d4a): the inbound wire +
# applier are already in place, and the local-cast emit on
# session.taunt_broadcaster is already wired by SpellEffectResolver;
# this module is the final hop that puts the (enemy_id, duration)
# tuple on the wire.
#
# Why a separate module (vs. an inline connect in CoopSession.start
# or a direct connect in lobby.gd):
#   - The broadcaster fan-out shape is per-cast; the wire layer's
#     send is fire-and-forget. Routing logic (read enemy_id+duration
#     off the signal, fire the lobby send) is a per-client concern
#     that doesn't belong inside TauntBroadcaster (would force solo
#     callers to pay for a wire dependency they don't need) and
#     doesn't belong inside NakamaLobby (its job is to encode/decode
#     packets, not subscribe to gameplay signals).
#   - As a RefCounted with explicit bind/unbind, the lifecycle is
#     testable in isolation: pin the rebind-replaces-old invariant,
#     pin the unbind-on-end teardown, pin the empty-input guards
#     without a live socket or session.
#
# Sibling-shaped to CoopXPSubscriber: same bind/unbind contract, same
# "construct around a signal, hold a connection, require unbind on
# teardown" lifecycle. Distinct from RemoteTauntApplier (a stateless
# static method on the inbound side) because outbound owns a live
# signal connection that must be torn down to prevent a dropped
# session from continuing to broadcast.
#
# caster_id is intentionally ignored from the emit tuple — Nakama
# tags every packet with the sender presence, so the receiving side
# reads caster_id off the socket envelope. Including it in the
# payload would let a tampered client spoof another player's TAUNT
# (same anti-spoof model as OP_POSITION / OP_KILL).

var _broadcaster: TauntBroadcaster = null
# Loosely typed so tests can pass a stub with just `send_taunt_async`
# without needing a live socket. Production callers always pass a
# NakamaLobby.
var _lobby = null

func _init(broadcaster: TauntBroadcaster = null, lobby = null) -> void:
	if broadcaster != null and lobby != null:
		bind(broadcaster, lobby)

# Connects to the broadcaster's taunt_applied signal. Returns true on
# a fresh bind, false on:
#   - null broadcaster / null lobby (either makes routing a no-op)
#   - already bound to this same broadcaster (idempotent — re-binding
#     would double-subscribe and fan duplicate packets on every emit)
# Re-binding to a *different* broadcaster transparently unbinds the
# old one first so the bridge can be reused across runs without the
# caller having to remember the unbind step.
func bind(broadcaster: TauntBroadcaster, lobby) -> bool:
	if broadcaster == null or lobby == null:
		return false
	if _broadcaster == broadcaster:
		return false
	if _broadcaster != null:
		unbind()
	_broadcaster = broadcaster
	_lobby = lobby
	_broadcaster.taunt_applied.connect(_on_taunt_applied)
	return true

# Disconnects from the bound broadcaster and clears the routing state.
# Returns true on a successful unbind, false on no-op (not currently
# bound). Called by CoopSession._drop_managers on session end so a
# dropped bridge doesn't keep firing send_taunt_async after the run.
func unbind() -> bool:
	if _broadcaster == null:
		return false
	if _broadcaster.taunt_applied.is_connected(_on_taunt_applied):
		_broadcaster.taunt_applied.disconnect(_on_taunt_applied)
	_broadcaster = null
	_lobby = null
	return true

func is_bound() -> bool:
	return _broadcaster != null

func _on_taunt_applied(_caster_id: String, enemy_id: String, duration: float) -> void:
	if _lobby == null:
		return
	_lobby.send_taunt_async(enemy_id, duration)
