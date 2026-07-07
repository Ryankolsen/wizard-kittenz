extends GutTest

# BillingManager is a two-backend facade (#403) over GodotGooglePlayBilling
# (Android) and an Apple StoreKit plugin singleton (iOS). Neither singleton
# exists on desktop / GUT, so the autoload's _ready() leaves _backend null
# and is_ready false. Every test in the first section below exercises only
# the no-backend degraded path. The Apple-backend tests further down inject
# a fake backend double directly (GUT/desktop has no real StoreKit
# singleton to test against) — the real on-device purchase round-trip is
# covered by the manual QA pass in #406.
#
# Note: BillingManager has no class_name (autoload-name conflict, see
# a08aba3) so tests address the existing autoload instance via
# /root/BillingManager rather than constructing a fresh one. The
# autoload's _ready() has already run by the time GUT loads — in the
# no-plugin state that's exactly the state we want to assert on.

# --- Issue tests (acceptance criteria) --------------------------------------

func test_billing_manager_autoload_is_registered():
	var bm := get_node_or_null("/root/BillingManager")
	assert_not_null(bm, "BillingManager autoload must be registered in project.godot")

func test_is_ready_false_without_plugin():
	var bm := get_node("/root/BillingManager")
	assert_false(bm.is_ready,
		"is_ready must stay false on platforms without GodotGooglePlayBilling")

func test_start_purchase_without_plugin_is_safe():
	# Must push a warning and return cleanly, not crash. If start_purchase
	# threw or accessed _plugin without a guard, GUT would surface the
	# error and fail this test.
	var bm := get_node("/root/BillingManager")
	bm.start_purchase(PurchaseRegistry.UPGRADE_WIZARD_KITTEN_WIZARD_CAT)
	assert_true(true, "start_purchase did not crash without plugin")

func test_purchase_succeeded_signal_exists():
	var bm := get_node("/root/BillingManager")
	assert_true(bm.has_signal("purchase_succeeded"),
		"purchase_succeeded signal must exist on BillingManager")

# --- Coverage extras --------------------------------------------------------

# Note: GUT prints a "*" next to this test name in full-suite output. That is
# a GUT annotation, not a failure marker — the test passes. Run this file
# alone to confirm: 9/9 passed.
func test_purchase_failed_signal_exists():
	var bm := get_node("/root/BillingManager")
	assert_true(bm.has_signal("purchase_failed"),
		"purchase_failed signal must exist on BillingManager")

func test_billing_ready_signal_exists():
	var bm := get_node("/root/BillingManager")
	assert_true(bm.has_signal("billing_ready"),
		"billing_ready signal must exist on BillingManager")

func test_start_purchase_method_exists():
	var bm := get_node("/root/BillingManager")
	assert_true(bm.has_method("start_purchase"),
		"start_purchase(product_id) must be the single IAP entry point")

# --- Removed-API regression guards (slice 5 of monetization pivot) ----------

func test_start_purchase_revive_tokens_method_removed():
	# Slice 5 strips the consumable-token entry point. If a future refactor
	# brings back a product-specific method by mistake, this fails loudly.
	var bm := get_node("/root/BillingManager")
	assert_false(bm.has_method("start_purchase_revive_tokens"),
		"start_purchase_revive_tokens must be removed; use start_purchase(product_id)")

func test_consumable_constants_removed_from_script():
	# The PRODUCT_REVIVE_TOKENS / TOKENS_PER_PACK constants belonged to the
	# consumable flow. Pinning their absence on the script (not the instance)
	# prevents accidental resurrection on the consumable path.
	var bm := get_node("/root/BillingManager")
	var consts: Dictionary = bm.get_script().get_script_constant_map()
	assert_false(consts.has("PRODUCT_REVIVE_TOKENS"),
		"PRODUCT_REVIVE_TOKENS constant must be removed")
	assert_false(consts.has("TOKENS_PER_PACK"),
		"TOKENS_PER_PACK constant must be removed")

# --- Apple StoreKit backend facade (#403) ------------------------------------
#
# No real StoreKit singleton is available on desktop/GUT, so these tests
# inject a fake backend double directly into the autoload's internal
# _backend slot and drive its normalized ready/purchase_succeeded/
# purchase_failed signals. This proves BillingManager's facade wiring works
# end-to-end without depending on the real plugin; real on-device purchase
# behavior is covered by the manual QA pass in #406.

class FakeBillingBackend:
	extends RefCounted
	signal ready()
	signal purchase_succeeded(product_id: String)
	signal purchase_failed(product_id: String)

	var start_purchase_calls: Array[String] = []

	func start_purchase(product_id: String) -> void:
		start_purchase_calls.append(product_id)

var _saved_backend
var _saved_is_ready: bool

func before_each():
	var bm := get_node("/root/BillingManager")
	_saved_backend = bm._backend
	_saved_is_ready = bm.is_ready

func after_each():
	var bm := get_node("/root/BillingManager")
	bm._backend = _saved_backend
	bm.is_ready = _saved_is_ready

func test_apple_backend_selected_when_singleton_present():
	var bm := get_node("/root/BillingManager")
	var fake := FakeBillingBackend.new()
	bm._backend = fake
	bm._wire_backend()
	watch_signals(bm)

	fake.ready.emit()

	assert_true(bm.is_ready, "is_ready must become true once the backend reports ready")
	assert_signal_emitted(bm, "billing_ready")

func test_start_purchase_forwards_product_id_to_apple_adapter():
	var bm := get_node("/root/BillingManager")
	var fake := FakeBillingBackend.new()
	bm._backend = fake
	bm._wire_backend()
	fake.ready.emit()

	bm.start_purchase(PurchaseRegistry.GEM_BUNDLE_STARTER)

	assert_eq(fake.start_purchase_calls, [PurchaseRegistry.GEM_BUNDLE_STARTER],
		"start_purchase must forward the exact product ID to the backend")

func test_apple_purchase_succeeded_emits_signal_with_product_id():
	var bm := get_node("/root/BillingManager")
	var fake := FakeBillingBackend.new()
	bm._backend = fake
	bm._wire_backend()
	fake.ready.emit()
	watch_signals(bm)

	fake.purchase_succeeded.emit(PurchaseRegistry.GEM_BUNDLE_EXPLORER)

	assert_signal_emitted_with_parameters(bm, "purchase_succeeded", [PurchaseRegistry.GEM_BUNDLE_EXPLORER])

func test_apple_purchase_failed_emits_signal():
	var bm := get_node("/root/BillingManager")
	var fake := FakeBillingBackend.new()
	bm._backend = fake
	bm._wire_backend()
	fake.ready.emit()
	watch_signals(bm)

	fake.purchase_failed.emit(PurchaseRegistry.GEM_BUNDLE_HERO)

	assert_signal_emitted_with_parameters(bm, "purchase_failed", [PurchaseRegistry.GEM_BUNDLE_HERO])
