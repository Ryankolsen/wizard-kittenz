extends GutTest

# BillingManager wraps the GodotGooglePlayBilling 3.x JNI singleton. That
# singleton only exists on real Android builds; on desktop / GUT it is
# absent and the autoload's _ready() returns early, leaving _plugin null
# and is_ready false. Every test here exercises only the no-plugin
# degraded path. The end-to-end purchase round-trip is covered by the
# manual QA pass in #34 on a real device.
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
	bm.start_purchase(PurchaseRegistry.UPGRADE_MAGE_ARCHMAGE)
	assert_true(true, "start_purchase did not crash without plugin")

func test_purchase_succeeded_signal_exists():
	var bm := get_node("/root/BillingManager")
	assert_true(bm.has_signal("purchase_succeeded"),
		"purchase_succeeded signal must exist on BillingManager")

# --- Coverage extras --------------------------------------------------------

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
