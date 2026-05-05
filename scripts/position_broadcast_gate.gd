class_name PositionBroadcastGate
extends RefCounted

# Pure-data outbound counterpart to NetworkSyncManager.apply_remote_state.
# Where NetworkSyncManager + RemotePlayerInterpolator handle the inbound
# side (a remote kitten's position arriving from the wire layer is fed
# into apply_remote_state and rendered via get_display_position_at), this
# gate handles the outbound side: the wire layer (#14, HITL) asks
# should_broadcast(now, position) each tick, and the gate decides whether
# to actually fan out a packet.
#
# Three rules combined per call:
#   1. Rate limit (min_interval_seconds): never broadcast more than once
#      per min_interval. Keeps a 60Hz physics tick from saturating the
#      wire with 60 packets/sec — default 0.1s = 10Hz max, the cadence
#      RemotePlayerInterpolator's two-slot buffer is sized for.
#   2. Delta gate (min_position_delta): if the kitten hasn't moved at
#      least min_position_delta pixels since last broadcast, don't send.
#      A stationary kitten (player AFK in a room) doesn't flood the wire
#      with redundant "still at (x, y)" packets.
#   3. Heartbeat (heartbeat_interval_seconds): even if stationary, force
#      a broadcast every heartbeat_interval seconds. Lets remote clients
#      detect "lost connection vs. just standing still" by timing the
#      gap between packets — without the heartbeat, a player who stands
#      perfectly still looks identical (over the wire) to a player whose
#      connection silently dropped.
#
# Sibling-shaped to the rest of the wire-layer scaffolding (DungeonSeedSync,
# RemoteKillApplier, KillRewardRouter): pure RefCounted, no I/O, no scene
# tree, instantiated per-match by the future co-op orchestrator.
#
# Lifecycle:
#   - Construct once per match (one gate per local player; remotes are
#     handled by the inbound NetworkSyncManager). Default thresholds
#     are sensible for a top-down kitten dungeon crawler at 480x270;
#     callers can override via the constructor or the property setters
#     before the first should_broadcast call (e.g. a future "low-bandwidth
#     mode" toggle could halve the cadence and double the heartbeat).
#   - Per-tick the wire layer calls should_broadcast(now, pos); on true,
#     it sends the packet AND calls mark_broadcast(now, pos). The two-
#     step API lets the wire layer abort the broadcast (e.g. socket
#     disconnect) without poisoning the gate's state.
#   - Or use the combined try_broadcast(now, pos) when the wire layer
#     has nothing to abort on — single call instead of should + mark.
#   - Reset between matches if reusing the same gate instance (RefCounted
#     drop is the simpler path; reset() is for the "play again" flow that
#     keeps the orchestrator alive across runs).
#
# What this does NOT do:
#   - Build the wire packet. The wire layer's outbound serializer
#     (Nakama-specific JSON / bytes shape) is its own concern; this gate
#     just answers "is now a good moment to send something?".
#   - Track per-remote-player broadcast state. The local kitten has one
#     gate; remote kittens are display-only on this client and don't
#     need outbound gating. A future "host broadcasts enemy state on
#     behalf of all clients" design might want a sibling EnemyBroadcastGate
#     keyed by enemy_id — same shape, different identity dimension.
#   - Extrapolate / dead-reckon. The interpolator's clamp-to-current
#     contract handles the "no fresh packet since last sample" case on
#     the inbound side; the heartbeat ensures fresh packets keep flowing
#     from the outbound side. Dead-reckoning would be a future
#     optimization that lives separately.
#   - Adapt thresholds based on observed bandwidth / RTT. A future
#     auto-tuning gate could read NetworkSyncManager's recent sample
#     timestamps to detect packet loss and back off cadence; current
#     gate is fixed-threshold for predictability.

const DEFAULT_MIN_INTERVAL_SECONDS: float = 0.1
const DEFAULT_MIN_POSITION_DELTA: float = 1.0
const DEFAULT_HEARTBEAT_INTERVAL_SECONDS: float = 1.0

var min_interval_seconds: float = DEFAULT_MIN_INTERVAL_SECONDS
var min_position_delta: float = DEFAULT_MIN_POSITION_DELTA
var heartbeat_interval_seconds: float = DEFAULT_HEARTBEAT_INTERVAL_SECONDS

var _last_broadcast_time: float = 0.0
var _last_broadcast_position: Vector2 = Vector2.ZERO
var _has_broadcast: bool = false

func _init(
	interval: float = DEFAULT_MIN_INTERVAL_SECONDS,
	delta: float = DEFAULT_MIN_POSITION_DELTA,
	heartbeat: float = DEFAULT_HEARTBEAT_INTERVAL_SECONDS,
) -> void:
	min_interval_seconds = interval
	min_position_delta = delta
	heartbeat_interval_seconds = heartbeat

# Predicate: should the wire layer fan out the local position right now?
#
# Returns true when at least one of:
#   - This is the first broadcast (no prior baseline — the first packet
#     after match start lets remote clients pop us in at the spawn point
#     immediately rather than waiting for the first delta or heartbeat).
#   - Enough time has passed since the last broadcast (>= min_interval)
#     AND the kitten moved at least min_position_delta since then.
#   - Enough time has passed since the last broadcast (>= min_interval)
#     AND the heartbeat window elapsed (force-send even if stationary).
#
# Returns false when:
#   - We're inside the rate-limit window (elapsed < min_interval),
#     regardless of how far the kitten moved. Defends against a 60Hz
#     physics tick saturating the wire on a single-frame teleport
#     (e.g. a power-up that snaps the player across the room).
#   - We're past the rate-limit but haven't moved enough AND the
#     heartbeat hasn't elapsed.
#
# Backwards-time defense: if `now` is BEFORE _last_broadcast_time
# (clock skew, suspended-process resume), elapsed is negative and the
# rate-limit branch returns false. The gate freezes until the wire
# layer's clock catches up — better than flooding the wire with rapid
# broadcasts during the catch-up window.
func should_broadcast(now: float, position: Vector2) -> bool:
	if not _has_broadcast:
		return true
	var elapsed: float = now - _last_broadcast_time
	if elapsed < min_interval_seconds:
		return false
	if elapsed >= heartbeat_interval_seconds:
		return true
	return position.distance_to(_last_broadcast_position) >= min_position_delta

# Marks that the wire layer broadcast the position at `now`. Caller
# invokes this AFTER the actual packet send so the gate's state reflects
# the new baseline. Two-step (should + mark) so the wire layer can
# abort the broadcast (e.g. socket disconnect) without poisoning the
# gate's state — a should_broadcast that returned true followed by no
# mark_broadcast simply means the next tick re-evaluates.
func mark_broadcast(now: float, position: Vector2) -> void:
	_last_broadcast_time = now
	_last_broadcast_position = position
	_has_broadcast = true

# Combined: returns true and updates state when should_broadcast says so;
# returns false and leaves state untouched otherwise. The wire layer's
# per-tick call site is one call instead of two when there's nothing to
# abort on:
#   if gate.try_broadcast(now, pos):
#       nakama.broadcast({"op": "pos", "x": pos.x, "y": pos.y, "ts": now})
func try_broadcast(now: float, position: Vector2) -> bool:
	if not should_broadcast(now, position):
		return false
	mark_broadcast(now, position)
	return true

func has_broadcast() -> bool:
	return _has_broadcast

func last_broadcast_time() -> float:
	return _last_broadcast_time

func last_broadcast_position() -> Vector2:
	return _last_broadcast_position

# Clears state so the same gate instance can be reused for the next
# match. The "play again" flow that keeps the co-op orchestrator alive
# calls reset() between runs; the simpler RefCounted drop-and-rebuild
# path also works (this is for callers who want to keep the gate's
# threshold overrides without re-constructing).
func reset() -> void:
	_has_broadcast = false
	_last_broadcast_time = 0.0
	_last_broadcast_position = Vector2.ZERO
