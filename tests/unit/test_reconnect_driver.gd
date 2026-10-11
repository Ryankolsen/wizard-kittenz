extends GutTest

# Tests for ReconnectDriver (#640, parent PRD #636) — the Node that wires
# ReconnectCoordinator (#638) to NakamaLobby's connection_lost/rebind_socket
# seam (#639) into a real-time retry loop. Mirrors test_nakama_lobby_reconnect's
# FakeSocket pattern for the lobby side; the network-call portion is replaced
# with an injected fake attempt-strategy Callable so no test depends on real
# NakamaService I/O or a real clock.

class FakeJoinResult:
	extends RefCounted
	var _is_exception: bool
	func _init(p_is_exception: bool) -> void:
		_is_exception = p_is_exception
	func is_exception() -> bool:
		return _is_exception

class FakeSocket:
	extends RefCounted
	signal closed()
	signal connection_error(p_error)
	signal received_match_presence(p_match_presence_event)
	signal received_match_state(p_match_state)

	# join_result is only populated on sockets the production strategy test
	# hands back from a fake NakamaService.create_socket_async — the lobby's
	# own FakeSocket never needs it.
	var join_result: FakeJoinResult = null

	func leave_match_async(_match_id: String):
		return null

	func send_match_state_async(_match_id: String, _op_code: int, _data: String, _presences = null):
		return null

	func join_match_async(_match_id: String):
		return join_result

# Queue-driven fake attempt strategy. Each call to attempt() pops the next
# queued result (defaulting to false if the queue is exhausted) and bumps
# call_count so tests can assert exactly how many real attempts fired.
class FakeStrategy:
	extends RefCounted
	var call_count: int = 0
	var results: Array = []

	func _init(p_results: Array = []) -> void:
		results = p_results

	func attempt() -> bool:
		call_count += 1
		if results.is_empty():
			return false
		return results.pop_front()

func _make_active_lobby(socket: FakeSocket, local_id: String = "local-1") -> NakamaLobby:
	var lobby := NakamaLobby.new(socket, null)
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make(local_id, "local-kitten", "Mage", true))
	lobby.local_player_id = local_id
	lobby._match_id = "match-1"
	return lobby

func _make_driver(lobby: NakamaLobby, strategy: FakeStrategy, interval: float = 5.0, window: float = 45.0) -> ReconnectDriver:
	var driver := ReconnectDriver.new(interval, window)
	add_child_autofree(driver)
	driver.set_attempt_strategy(Callable(strategy, "attempt"))
	driver.set_lobby(lobby)
	return driver

# --- Core wiring -------------------------------------------------------------

func test_lobby_connection_lost_starts_retrying():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var strategy := FakeStrategy.new([])
	var driver := _make_driver(lobby, strategy)
	watch_signals(driver)

	socket.closed.emit()

	assert_signal_emitted(driver, "reconnect_started")

# --- Content details -----------------------------------------------------------

func test_first_tick_after_drop_invokes_strategy_once():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var strategy := FakeStrategy.new([false])
	var driver := _make_driver(lobby, strategy)

	socket.closed.emit()
	driver._tick(0.0)

	assert_eq(strategy.call_count, 1)

func test_tick_before_interval_elapsed_does_not_reinvoke_strategy():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var strategy := FakeStrategy.new([false, false])
	var driver := _make_driver(lobby, strategy, 5.0, 45.0)

	socket.closed.emit()
	driver._tick(0.0)
	driver._tick(2.0)

	assert_eq(strategy.call_count, 1)

func test_tick_after_interval_elapsed_reinvokes_strategy():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var strategy := FakeStrategy.new([false, false])
	var driver := _make_driver(lobby, strategy, 5.0, 45.0)

	socket.closed.emit()
	driver._tick(0.0)
	driver._tick(5.0)

	assert_eq(strategy.call_count, 2)

func test_successful_attempt_forwards_succeeded_and_stops_retrying():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var strategy := FakeStrategy.new([true])
	var driver := _make_driver(lobby, strategy, 5.0, 45.0)
	watch_signals(driver)

	socket.closed.emit()
	driver._tick(0.0)

	assert_signal_emitted(driver, "reconnect_succeeded")

	driver._tick(10.0)
	assert_eq(strategy.call_count, 1)

func test_exhausted_after_window_forwards_exhausted():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var strategy := FakeStrategy.new([false, false])
	var driver := _make_driver(lobby, strategy, 5.0, 45.0)
	watch_signals(driver)

	socket.closed.emit()
	driver._tick(0.0)
	driver._tick(50.0)

	assert_signal_emitted(driver, "reconnect_exhausted")

func test_production_strategy_success_path_calls_rebind_socket():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var driver := ReconnectDriver.new()
	add_child_autofree(driver)
	driver.set_lobby(lobby)

	var new_socket := FakeSocket.new()
	new_socket.join_result = FakeJoinResult.new(false)
	var fake_service := FakeNakamaService.new(new_socket)
	var fake_session := FakeSession.new()

	var success: bool = await driver._production_attempt_with(fake_service, fake_session)

	assert_true(success)
	assert_eq(lobby._socket, new_socket)

# --- Edge cases / error paths --------------------------------------------------

func test_cancel_reconnect_forces_exhausted():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var strategy := FakeStrategy.new([false])
	var driver := _make_driver(lobby, strategy, 5.0, 45.0)
	watch_signals(driver)

	socket.closed.emit()
	driver.cancel_reconnect()

	assert_signal_emitted(driver, "reconnect_exhausted")

	driver._tick(100.0)
	assert_eq(strategy.call_count, 0)

func test_set_lobby_swap_disconnects_previous_lobby_signal():
	var socket_a := FakeSocket.new()
	var lobby_a := _make_active_lobby(socket_a, "local-1")
	var socket_b := FakeSocket.new()
	var lobby_b := _make_active_lobby(socket_b, "local-2")
	var strategy := FakeStrategy.new([])
	var driver := _make_driver(lobby_a, strategy)

	driver.set_lobby(lobby_b)
	watch_signals(driver)

	socket_a.closed.emit()

	assert_signal_not_emitted(driver, "reconnect_started")

func test_production_strategy_failed_create_socket_never_calls_rebind():
	var socket := FakeSocket.new()
	var lobby := _make_active_lobby(socket)
	var driver := ReconnectDriver.new()
	add_child_autofree(driver)
	driver.set_lobby(lobby)

	var fake_service := FakeNakamaService.new(null)
	var fake_session := FakeSession.new()

	var success: bool = await driver._production_attempt_with(fake_service, fake_session)

	assert_false(success)
	assert_eq(lobby._socket, socket)

# Minimal fake standing in for the NakamaService autoload shape the
# production strategy calls through: create_socket_async(session) and,
# on the returned socket, join_match_async(match_id).
class FakeSession:
	extends RefCounted

class FakeNakamaService:
	extends RefCounted
	var _socket_to_return

	func _init(socket_to_return) -> void:
		_socket_to_return = socket_to_return

	func create_socket_async(_session):
		return _socket_to_return
