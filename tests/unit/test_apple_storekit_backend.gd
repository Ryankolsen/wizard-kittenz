extends GutTest

# Unit coverage for AppleStoreKitBackend's polling logic against a fake
# plugin double that mirrors the real InAppStore plugin's surface (verified
# against godotengine/godot-ios-plugins source — see comment header on
# apple_storekit_backend.gd). BillingManager-level facade wiring (ready /
# purchase_succeeded / purchase_failed forwarding) is covered separately in
# test_billing_manager.gd via FakeBillingBackend; this file exercises the
# request_product_info -> purchase -> finish_transaction event sequence
# that FakeBillingBackend deliberately skips over.

class FakePlugin:
	extends RefCounted

	var auto_finish_set: bool = true
	var requested_product_ids: Array[String] = []
	var purchased_product_ids: Array[String] = []
	var finished_product_ids: Array[String] = []
	var restore_called: bool = false
	var request_product_info_error: int = OK
	var purchase_error: int = OK

	var _events: Array[Dictionary] = []

	func set_auto_finish_transaction(flag: bool) -> void:
		auto_finish_set = flag

	func restore_purchases() -> int:
		restore_called = true
		return OK

	func request_product_info(params: Dictionary) -> int:
		var ids: PackedStringArray = params.get("product_ids", PackedStringArray())
		for id in ids:
			requested_product_ids.append(id)
		return request_product_info_error

	func purchase(params: Dictionary) -> int:
		purchased_product_ids.append(String(params.get("product_id", "")))
		return purchase_error

	func finish_transaction(product_id: String) -> void:
		finished_product_ids.append(product_id)

	func get_pending_event_count() -> int:
		return _events.size()

	func pop_pending_event() -> Dictionary:
		return _events.pop_front()

	func push_event(event: Dictionary) -> void:
		_events.append(event)

func test_start_sets_auto_finish_false_and_restores_then_emits_ready():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	watch_signals(backend)

	backend.start()

	assert_false(plugin.auto_finish_set, "backend must finish transactions itself, not rely on plugin auto-finish")
	assert_true(plugin.restore_called, "start() must call restore_purchases to surface prior purchases")
	assert_signal_emitted(backend, "ready")

func test_start_purchase_requests_product_info():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	backend.start()

	backend.start_purchase("gem_bundle_starter")

	assert_eq(plugin.requested_product_ids, ["gem_bundle_starter"])
	assert_eq(plugin.purchased_product_ids, [], "purchase() must wait for the product_info event, not fire immediately")

func test_product_info_ok_triggers_purchase_call():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	backend.start()
	backend.start_purchase("gem_bundle_starter")

	plugin.push_event({"result": "ok", "type": "product_info", "invalid_ids": []})
	backend.poll()

	assert_eq(plugin.purchased_product_ids, ["gem_bundle_starter"])

func test_product_info_invalid_id_emits_purchase_failed():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	watch_signals(backend)
	backend.start()
	backend.start_purchase("gem_bundle_starter")

	plugin.push_event({"result": "ok", "type": "product_info", "invalid_ids": ["gem_bundle_starter"]})
	backend.poll()

	assert_push_error("invalid", "an invalid product id must be logged")
	assert_eq(plugin.purchased_product_ids, [], "must not call purchase() for an invalid product id")
	assert_signal_emitted_with_parameters(backend, "purchase_failed", ["gem_bundle_starter"])

func test_purchase_ok_finishes_transaction_and_emits_succeeded():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	watch_signals(backend)
	backend.start()
	backend.start_purchase("gem_bundle_hero")
	plugin.push_event({"result": "ok", "type": "product_info", "invalid_ids": []})
	backend.poll()

	plugin.push_event({"result": "ok", "type": "purchase", "product_id": "gem_bundle_hero"})
	backend.poll()

	assert_eq(plugin.finished_product_ids, ["gem_bundle_hero"],
		"a successful purchase must be finished so StoreKit doesn't redeliver it forever")
	assert_signal_emitted_with_parameters(backend, "purchase_succeeded", ["gem_bundle_hero"])

func test_purchase_error_emits_failed_without_finishing():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	watch_signals(backend)
	backend.start()
	backend.start_purchase("gem_bundle_hero")
	plugin.push_event({"result": "ok", "type": "product_info", "invalid_ids": []})
	backend.poll()

	plugin.push_event({"result": "error", "type": "purchase", "product_id": "gem_bundle_hero"})
	backend.poll()

	assert_push_error("purchase error", "a failed purchase must be logged")
	assert_eq(plugin.finished_product_ids, [], "an errored purchase must not be finished")
	assert_signal_emitted_with_parameters(backend, "purchase_failed", ["gem_bundle_hero"])

func test_purchase_progress_event_does_not_resolve_yet():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	watch_signals(backend)
	backend.start()
	backend.start_purchase("gem_bundle_hero")
	plugin.push_event({"result": "ok", "type": "product_info", "invalid_ids": []})
	backend.poll()

	plugin.push_event({"result": "progress", "type": "purchase", "product_id": "gem_bundle_hero"})
	backend.poll()

	assert_signal_not_emitted(backend, "purchase_succeeded")
	assert_signal_not_emitted(backend, "purchase_failed")

func test_restore_event_finishes_transaction_and_emits_succeeded():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	watch_signals(backend)
	backend.start()

	plugin.push_event({"result": "ok", "type": "restore", "product_id": "gem_bundle_explorer"})
	backend.poll()

	assert_eq(plugin.finished_product_ids, ["gem_bundle_explorer"])
	assert_signal_emitted_with_parameters(backend, "purchase_succeeded", ["gem_bundle_explorer"])

func test_completed_event_is_a_safe_noop():
	var plugin := FakePlugin.new()
	var backend := AppleStoreKitBackend.new(plugin)
	watch_signals(backend)
	backend.start()

	plugin.push_event({"result": "ok", "type": "completed"})
	backend.poll()

	assert_signal_not_emitted(backend, "purchase_succeeded")
	assert_signal_not_emitted(backend, "purchase_failed")
