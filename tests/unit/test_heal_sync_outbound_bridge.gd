extends GutTest

# Sibling class_name resolution is fragile in Godot 4.x for freshly-
# added classes; preload sidesteps the registry lookup.
const HealSyncOutboundBridgeRef = preload("res://scripts/networking/heal_sync_outbound_bridge.gd")
const HealBroadcasterRef = preload("res://scripts/networking/heal_broadcaster.gd")

# Unit tests for HealSyncOutboundBridge — the outbound wire half of the
# co-op Sleepy Kitten heal/buff loop. Sibling-shaped to
# TauntSyncOutboundBridge tests.

class StubLobby:
	extends RefCounted
	var calls: Array = []
	func send_heal_async(target_id: String, effect_kind: String, amount: int, duration: float) -> void:
		calls.append([target_id, effect_kind, amount, duration])

func test_bind_subscribes_to_broadcaster():
	var bc = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new()
	assert_true(bridge.bind(bc, stub), "fresh bind returns true")
	assert_true(bridge.is_bound())

func test_heal_applied_routes_to_lobby_send_heal_async():
	# Core fan-out: a broadcaster emission becomes a single
	# send_heal_async with (target_id, effect_kind, amount, duration).
	# caster_id is intentionally NOT forwarded — receiver reads it off
	# the socket envelope (anti-spoof model).
	var bc = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new(bc, stub)
	bc.on_heal_applied("u1", "u2", "AOE_HEAL", 5, 0.0)
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0][0], "u2")
	assert_eq(stub.calls[0][1], "AOE_HEAL")
	assert_eq(stub.calls[0][2], 5)
	assert_eq(stub.calls[0][3], 0.0)

func test_party_buff_two_emissions_fan_independently():
	# PARTY_BUFF (Cozy Aura) emits two tuples per target (defense + MR);
	# the bridge must forward both as separate wire packets so the
	# receiver applies each stat delta independently.
	var bc = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new(bc, stub)
	bc.on_heal_applied("u1", "u2", "PARTY_BUFF_DEFENSE", 3, 15.0)
	bc.on_heal_applied("u1", "u2", "PARTY_BUFF_MAGIC_RESISTANCE", 3, 15.0)
	assert_eq(stub.calls.size(), 2)
	assert_eq(stub.calls[0][1], "PARTY_BUFF_DEFENSE")
	assert_eq(stub.calls[1][1], "PARTY_BUFF_MAGIC_RESISTANCE")

func test_group_regen_forwards_duration():
	var bc = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new(bc, stub)
	bc.on_heal_applied("u1", "u2", "GROUP_REGEN", 2, 15.0)
	assert_eq(stub.calls[0][2], 2)
	assert_eq(stub.calls[0][3], 15.0)

func test_unbind_disconnects_and_stops_routing():
	var bc = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new(bc, stub)
	assert_true(bridge.unbind())
	assert_false(bridge.is_bound())
	bc.on_heal_applied("u1", "u2", "AOE_HEAL", 5, 0.0)
	assert_eq(stub.calls.size(), 0, "no fan-out after unbind")

func test_unbind_idempotent_when_not_bound():
	var bridge = HealSyncOutboundBridgeRef.new()
	assert_false(bridge.unbind())

func test_bind_rejects_null_broadcaster():
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new()
	assert_false(bridge.bind(null, stub))
	assert_false(bridge.is_bound())

func test_bind_rejects_null_lobby():
	var bc = HealBroadcasterRef.new()
	var bridge = HealSyncOutboundBridgeRef.new()
	assert_false(bridge.bind(bc, null))
	assert_false(bridge.is_bound())

func test_bind_idempotent_when_already_bound_to_same_broadcaster():
	var bc = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new(bc, stub)
	assert_false(bridge.bind(bc, stub))
	bc.on_heal_applied("u1", "u2", "AOE_HEAL", 5, 0.0)
	assert_eq(stub.calls.size(), 1, "only one send despite the double bind attempt")

func test_rebind_to_different_broadcaster_unbinds_old():
	var bc1 = HealBroadcasterRef.new()
	var bc2 = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new(bc1, stub)
	assert_true(bridge.bind(bc2, stub))
	bc1.on_heal_applied("u1", "u2", "AOE_HEAL", 5, 0.0)
	assert_eq(stub.calls.size(), 0, "old broadcaster no longer fans through bridge")
	bc2.on_heal_applied("u1", "u3", "SMART_HEAL", 3, 0.0)
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0][0], "u3")

func test_init_with_nulls_leaves_unbound():
	var bridge = HealSyncOutboundBridgeRef.new()
	assert_false(bridge.is_bound())

func test_empty_target_id_aoe_sentinel_forwarded():
	# Empty target_id is the AOE/party-wide sentinel — bridge must NOT
	# filter it out (the wire layer and receiver are responsible for
	# fan-out).
	var bc = HealBroadcasterRef.new()
	var stub := StubLobby.new()
	var bridge = HealSyncOutboundBridgeRef.new(bc, stub)
	bc.on_heal_applied("u1", "", "AOE_HEAL", 5, 0.0)
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0][0], "", "empty target_id preserved on the wire")
