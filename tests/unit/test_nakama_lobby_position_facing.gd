extends GutTest

# Tests for slice 2 of co-op parity (PRD #328, issue #330). OP_POSITION
# gained an optional facing_x sign so RemoteKitten can mirror the sender's
# sprite flip. The wire stays the same opcode; backward compat with a
# pre-#330 sender (no facing_x key) is "facing_x defaults to 0", which
# RemoteKitten treats as "keep last known facing" — same as a stationary
# local Player whose horizontal input is zero.

class MockSocket:
	extends RefCounted
	var sent: Array = []

	func send_match_state_async(match_id: String, op_code: int, raw: String) -> void:
		sent.append({"match_id": match_id, "op_code": op_code, "raw": raw})


func _make_lobby_with_socket() -> Dictionary:
	var lobby := NakamaLobby.new()
	var mock := MockSocket.new()
	lobby._socket = mock
	lobby._match_id = "match-abc"
	lobby.local_player_id = "me"
	return {"lobby": lobby, "socket": mock}


func test_apply_state_op_position_emits_facing_x_from_payload():
	# Receiver decodes facing_x off the wire and surfaces it as the 4th
	# signal parameter so the render layer can flip the matching
	# RemoteKitten without a second packet.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id",
		{"x": 1.0, "y": 2.0, "ts": 0.5, "facing_x": -1})
	var params: Array = get_signal_parameters(lobby, "position_received")
	assert_eq(params[3], -1, "facing_x decoded from payload")
	# Existing fields must keep flowing through alongside the new one.
	assert_eq(params[0], "remote_id")
	assert_eq(params[1], Vector2(1, 2))
	assert_eq(params[2], 0.5)


func test_apply_state_op_position_facing_x_positive():
	# Positive sign is the symmetric case of the -1 test: pin the value
	# decodes literally rather than going through abs() or sign().
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id",
		{"x": 1.0, "y": 2.0, "ts": 0.5, "facing_x": 1})
	var params: Array = get_signal_parameters(lobby, "position_received")
	assert_eq(params[3], 1, "facing_x decoded as +1")


func test_apply_state_op_position_missing_facing_x_defaults_zero():
	# Backward-compat: a pre-#330 sender's payload won't carry the key.
	# Receiver must surface 0, which downstream treats as "keep last
	# known facing". Confirms the decode path can't crash on absence.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id",
		{"x": 1.0, "y": 2.0, "ts": 0.5})
	assert_signal_emitted(lobby, "position_received")
	var params: Array = get_signal_parameters(lobby, "position_received")
	assert_eq(params[3], 0, "missing key surfaces as 0 sentinel")


func test_apply_state_op_position_explicit_zero_facing_x():
	# An explicit zero (player whose data.facing is purely vertical, or
	# default Vector2.DOWN at game start) must round-trip as zero rather
	# than getting coerced to something else by JSON.parse_string +
	# int() casting.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_POSITION, "remote_id",
		{"x": 1.0, "y": 2.0, "ts": 0.5, "facing_x": 0})
	var params: Array = get_signal_parameters(lobby, "position_received")
	assert_eq(params[3], 0)


func test_send_position_async_writes_facing_x_into_payload():
	# Sender side: the OP_POSITION payload carries facing_x verbatim so
	# the receiver's _route_position decode picks it up. Pinned via mock
	# socket capture of the JSON-serialized raw bytes.
	var fixture := _make_lobby_with_socket()
	var lobby: NakamaLobby = fixture["lobby"]
	var mock: MockSocket = fixture["socket"]
	await lobby.send_position_async(1.25, Vector2(7, 8), -1)
	assert_eq(mock.sent.size(), 1)
	var pkt: Dictionary = mock.sent[0]
	assert_eq(pkt["op_code"], NakamaLobby.OP_POSITION)
	var parsed = JSON.parse_string(pkt["raw"])
	assert_eq(parsed["facing_x"], -1, "facing_x serialized into payload")
	# Existing fields must still be written so this slice doesn't
	# silently regress the position interpolator.
	assert_eq(parsed["x"], 7.0)
	assert_eq(parsed["y"], 8.0)
	assert_eq(parsed["ts"], 1.25)


func test_send_position_async_defaults_facing_x_zero_when_omitted():
	# Defense-in-depth on the default-arg path: a caller that hasn't been
	# updated to pass facing_x must still emit a valid packet (facing_x = 0
	# = no-op on the receiver).
	var fixture := _make_lobby_with_socket()
	var lobby: NakamaLobby = fixture["lobby"]
	var mock: MockSocket = fixture["socket"]
	await lobby.send_position_async(0.5, Vector2(1, 2))
	var parsed = JSON.parse_string(mock.sent[0]["raw"])
	assert_eq(parsed["facing_x"], 0)
