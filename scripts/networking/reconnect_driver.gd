class_name ReconnectDriver
extends Node

# Real-time wire-up of ReconnectCoordinator (#638, pure retry/backoff
# decision machine) and NakamaLobby's connection_lost/rebind_socket seam
# (#639) into an actual reconnect loop (#640, parent PRD #636).
#
# Responsibilities:
#   - Owns one ReconnectCoordinator and a reference to the active NakamaLobby.
#   - On the lobby's connection_lost, starts a retry cycle.
#   - A real, short-interval Timer calls _tick(now) every ~1s — far finer-
#     grained than the coordinator's own ~5s retry interval, since the
#     Timer's only job is to keep polling "is it time yet", not to pace the
#     retries itself (that pacing lives in ReconnectCoordinator).
#   - On each tick where the coordinator says it's time, performs a real
#     reconnect attempt via an injectable _attempt_strategy Callable —
#     production code defaults to _production_attempt (fresh socket on the
#     existing session, rejoin the cached match id, rebind_socket on
#     success); tests inject a fake Callable so nothing here ever awaits
#     real network I/O in a unit test.
#   - Forwards the coordinator's three signals 1:1 so a future UI slice
#     (#641) can bind to the driver without reaching into the coordinator.
#
# What this does NOT do: any retry/backoff timing logic of its own (that's
# ReconnectCoordinator's job — this class only supplies the clock and the
# network call), or anything UI-facing (#641).

signal reconnect_started
signal reconnect_succeeded
signal reconnect_exhausted

const TICK_INTERVAL_SECONDS: float = 1.0

var _coordinator: ReconnectCoordinator
var _lobby: NakamaLobby = null
var _attempt_strategy: Callable
var _timer: Timer = null
var _retry_window_seconds: float
var _cycle_start_time: float = 0.0
# Most recent `now` this driver has observed, from either a real Timer tick
# or a test's direct _tick(now) call. connection_lost carries no `now` of
# its own (it's a plain signal, fired by the socket layer, not by the
# clock), so _on_connection_lost anchors the new cycle's start to whatever
# clock reading this driver last saw rather than re-querying the real clock
# independently. In production the real Timer ticks every ~1s, so this is
# at most ~1s stale — negligible against 5s/45s retry timing. In tests,
# this is what keeps a connection_lost fired before any _tick() call
# anchored at 0.0, so hand-picked `now` values in later _tick(now) calls
# stay in the same clock domain as the cycle's start instead of being
# compared against an unrelated real wall-clock reading (which would make
# window-expiry behavior depend on how long the test process had already
# been running before this test executed).
var _last_now: float = 0.0

func _init(
	retry_interval_seconds: float = ReconnectCoordinator.DEFAULT_RETRY_INTERVAL_SECONDS,
	retry_window_seconds: float = ReconnectCoordinator.DEFAULT_RETRY_WINDOW_SECONDS,
) -> void:
	_retry_window_seconds = retry_window_seconds
	_coordinator = ReconnectCoordinator.new(retry_interval_seconds, retry_window_seconds)
	_coordinator.reconnect_started.connect(func(): reconnect_started.emit())
	_coordinator.reconnect_succeeded.connect(func(): reconnect_succeeded.emit())
	_coordinator.reconnect_exhausted.connect(func(): reconnect_exhausted.emit())
	_attempt_strategy = Callable(self, "_production_attempt")

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_INTERVAL_SECONDS
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_timer_timeout)
	_timer.start()

func _on_timer_timeout() -> void:
	_tick(Time.get_ticks_msec() / 1000.0)

# Testability seam (#640): the real-time Timer only ever calls this with a
# live clock reading. Tests call it directly with hand-picked `now` values
# so nothing has to wait out a real 45-second retry window.
#
# ReconnectCoordinator.ready_for_next_attempt deliberately never transitions
# to EXHAUSTED on window expiry by itself (see its own doc comment) — that
# transition only happens via note_attempt_result's failure path or an
# explicit cancel(). A RETRYING cycle whose window has elapsed without a
# qualifying attempt landing in time would otherwise sit RETRYING forever,
# silently never attempting again and never telling anyone it gave up. The
# driver is the one real-time-aware party here, so it's the one that notices
# that case (state still RETRYING, but the window the driver itself was
# constructed with has elapsed since the cycle started) and forces the
# terminal transition via cancel().
func _tick(now: float) -> bool:
	_last_now = now
	if not _coordinator.ready_for_next_attempt(now):
		if _coordinator.state() == ReconnectCoordinator.State.RETRYING \
				and now - _cycle_start_time >= _retry_window_seconds:
			_coordinator.cancel()
		return false
	var success: bool = bool(_attempt_strategy.call())
	_coordinator.note_attempt_result(now, success)
	return true

# Injection seam for tests (and any future alternate network strategy) —
# defaults to _production_attempt in production.
func set_attempt_strategy(strategy: Callable) -> void:
	_attempt_strategy = strategy

# Wires the driver to the currently-active lobby, disconnecting any
# previous lobby's connection_lost first so a lobby swap (e.g. leaving one
# match and joining another) can't leave a stale connection firing a
# reconnect cycle for a lobby nobody cares about anymore. Mirrors
# GameState._disconnect_lobby_signals' is_connected-guarded teardown shape.
func set_lobby(new_lobby: NakamaLobby) -> void:
	if _lobby != null and _lobby.connection_lost.is_connected(_on_connection_lost):
		_lobby.connection_lost.disconnect(_on_connection_lost)
	_lobby = new_lobby
	if _lobby != null:
		_lobby.connection_lost.connect(_on_connection_lost)

func _on_connection_lost() -> void:
	_cycle_start_time = _last_now
	_coordinator.start(_last_now)

# Passthrough for a future UI "give up" button (#641).
func cancel_reconnect() -> void:
	_coordinator.cancel()

# Production reconnect attempt: fresh socket on the existing (long-lived)
# session, rejoin the lobby's cached match id, hand the new socket to the
# lobby via rebind_socket on success. Delegates to _production_attempt_with
# so a test can exercise the exact same logic with fakes standing in for
# the NakamaService autoload and session, without touching the real
# network-call path.
func _production_attempt() -> bool:
	return await _production_attempt_with(NakamaService, NakamaService.session)

func _production_attempt_with(service, session) -> bool:
	if _lobby == null:
		return false
	var new_socket = await service.create_socket_async(session)
	if new_socket == null:
		return false
	var join_result = await new_socket.join_match_async(_lobby.match_id())
	if join_result == null or join_result.is_exception():
		return false
	_lobby.rebind_socket(new_socket, session)
	return true
