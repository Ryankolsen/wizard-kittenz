extends GutTest

# Sibling class_name resolution is fragile in Godot 4.x for freshly-
# added classes; preload sidesteps the registry lookup.
const TauntSyncOutboundBridgeRef = preload("res://scripts/networking/taunt_sync_outbound_bridge.gd")

# Unit tests for TauntSyncOutboundBridge — the outbound wire half of the
# co-op TAUNT loop. Pins the bind/unbind lifecycle, the broadcaster ->
# lobby.send_taunt_async fan-out shape, and the guard branches that
# protect against double-binding or post-end emissions.
#
# The lobby parameter is loosely typed so this test uses a minimal stub
# that records every send_taunt_async call. The production caller is
# NakamaLobby; its own wire-encoding tests live in test_nakama_lobby_taunt.

class StubLobby:
	extends RefCounted
	var calls: Array = []
	func send_taunt_async(enemy_id: String, duration: float) -> void:
		calls.append([enemy_id, duration])

func test_bind_subscribes_to_broadcaster():
	# Rising-edge bind connects the signal and returns true so the caller
	# can tell a fresh wire from a duplicate.
	var bc := TauntBroadcaster.new()
	var stub := StubLobby.new()
	var bridge := TauntSyncOutboundBridgeRef.new()
	assert_true(bridge.bind(bc, stub), "fresh bind returns true")
	assert_true(bridge.is_bound(), "bridge reports bound state")

func test_taunt_applied_routes_to_lobby_send_taunt_async():
	# The core fan-out: when the local resolver emits on the broadcaster,
	# the bridge calls lobby.send_taunt_async with (enemy_id, duration).
	# caster_id is intentionally NOT forwarded — the receiving side reads
	# it off the socket envelope (anti-spoof model).
	var bc := TauntBroadcaster.new()
	var stub := StubLobby.new()
	var bridge := TauntSyncOutboundBridgeRef.new(bc, stub)
	bc.on_taunt_applied("u1", "r3_e0", 2.5)
	assert_eq(stub.calls.size(), 1, "one emission produces one send")
	assert_eq(stub.calls[0][0], "r3_e0", "enemy_id forwarded")
	assert_eq(stub.calls[0][1], 2.5, "duration forwarded")

func test_multiple_emissions_fan_independently():
	# Per-cast packets — no debouncing. Two TAUNTs on two enemies
	# produce two distinct send_taunt_async calls in order.
	var bc := TauntBroadcaster.new()
	var stub := StubLobby.new()
	var bridge := TauntSyncOutboundBridgeRef.new(bc, stub)
	bc.on_taunt_applied("u1", "r3_e0", 2.0)
	bc.on_taunt_applied("u1", "r3_e1", 3.0)
	assert_eq(stub.calls.size(), 2)
	assert_eq(stub.calls[0][0], "r3_e0")
	assert_eq(stub.calls[1][0], "r3_e1")
	assert_eq(stub.calls[1][1], 3.0)

func test_unbind_disconnects_and_stops_routing():
	# Post-end teardown: unbind drops the connection so a stale bridge
	# can't keep fanning packets after the session ended. The broadcaster
	# is allowed to keep emitting (other subscribers may exist) — only
	# the wire half goes dark.
	var bc := TauntBroadcaster.new()
	var stub := StubLobby.new()
	var bridge := TauntSyncOutboundBridgeRef.new(bc, stub)
	assert_true(bridge.unbind(), "unbind returns true on rising edge")
	assert_false(bridge.is_bound())
	bc.on_taunt_applied("u1", "r3_e0", 2.0)
	assert_eq(stub.calls.size(), 0, "no fan-out after unbind")

func test_unbind_idempotent_when_not_bound():
	# A double-unbind (e.g. session.end() called twice) is a no-op rather
	# than an error — matches CoopXPSubscriber.unbind's contract.
	var bridge := TauntSyncOutboundBridgeRef.new()
	assert_false(bridge.unbind(), "unbind returns false when never bound")

func test_bind_rejects_null_broadcaster():
	# Defensive: a null broadcaster would crash on the signal connect.
	# Surface the bad wiring at bind time, not on the first emission.
	var stub := StubLobby.new()
	var bridge := TauntSyncOutboundBridgeRef.new()
	assert_false(bridge.bind(null, stub), "null broadcaster rejected")
	assert_false(bridge.is_bound())

func test_bind_rejects_null_lobby():
	# Symmetric guard: a null lobby would crash on the first emission's
	# send_taunt_async call. Reject at bind time so the failure is
	# obvious rather than latent.
	var bc := TauntBroadcaster.new()
	var bridge := TauntSyncOutboundBridgeRef.new()
	assert_false(bridge.bind(bc, null), "null lobby rejected")
	assert_false(bridge.is_bound())

func test_bind_idempotent_when_already_bound_to_same_broadcaster():
	# Double-bind to the same broadcaster would double-subscribe and
	# fan two packets per emission. Same idempotency invariant as
	# CoopXPSubscriber.bind.
	var bc := TauntBroadcaster.new()
	var stub := StubLobby.new()
	var bridge := TauntSyncOutboundBridgeRef.new(bc, stub)
	assert_false(bridge.bind(bc, stub), "second bind to same broadcaster rejected")
	bc.on_taunt_applied("u1", "r3_e0", 2.0)
	assert_eq(stub.calls.size(), 1, "only one send despite the double bind attempt")

func test_rebind_to_different_broadcaster_unbinds_old():
	# Reuse-across-runs: a session end() drops the per-run broadcaster
	# and start() builds a new one. If the bridge is reused, the new
	# bind must transparently disconnect from the old broadcaster so a
	# leftover emission doesn't fire on a stale wire.
	var bc1 := TauntBroadcaster.new()
	var bc2 := TauntBroadcaster.new()
	var stub := StubLobby.new()
	var bridge := TauntSyncOutboundBridgeRef.new(bc1, stub)
	assert_true(bridge.bind(bc2, stub), "rebind to new broadcaster succeeds")
	bc1.on_taunt_applied("u1", "r3_e0", 2.0)
	assert_eq(stub.calls.size(), 0, "old broadcaster no longer fans through bridge")
	bc2.on_taunt_applied("u1", "r3_e1", 3.0)
	assert_eq(stub.calls.size(), 1, "new broadcaster routes normally")
	assert_eq(stub.calls[0][0], "r3_e1")

func test_init_with_nulls_leaves_unbound():
	# Default construction (no args) is the test / pre-handshake shape:
	# the bridge exists but has nothing wired. First bind() activates it.
	var bridge := TauntSyncOutboundBridgeRef.new()
	assert_false(bridge.is_bound())
