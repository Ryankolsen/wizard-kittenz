extends Node

# Wraps the GodotGooglePlayBilling Android plugin. On desktop/test builds the
# plugin singleton is absent — all methods degrade gracefully without crashing.
#
# Plugin binary required in android/plugins/:
#   GodotGooglePlayBilling.aar
#   GodotGooglePlayBilling.gdap
# Download from: https://github.com/godot-sdk-integrations/godot-google-play-billing/releases
# Then enable "Godot Google Play Billing" in Project > Export > Android > Plugins.

const PRODUCT_REVIVE_TOKENS := "revive_token_pack_5"
const TOKENS_PER_PACK := 5

signal billing_ready()
signal purchase_succeeded(product_id: String, tokens: int)
signal purchase_failed(product_id: String)

var is_ready := false

var _plugin = null
var _pending_product_details = null

func _ready() -> void:
	if Engine.has_singleton("GodotGooglePlayBilling"):
		_plugin = Engine.get_singleton("GodotGooglePlayBilling")
		_plugin.connected.connect(_on_connected)
		_plugin.connect_error.connect(_on_connect_error)
		_plugin.product_details_query_completed.connect(_on_product_details_query_completed)
		_plugin.product_details_query_error.connect(_on_product_details_query_error)
		_plugin.purchases_updated.connect(_on_purchases_updated)
		_plugin.purchase_error.connect(_on_purchase_error)
		_plugin.startConnection()
	else:
		push_warning("BillingManager: GodotGooglePlayBilling not available (not an Android build)")

func start_purchase_revive_tokens() -> void:
	if _plugin == null:
		push_warning("BillingManager: purchase skipped — plugin not available")
		return
	if not is_ready:
		push_warning("BillingManager: purchase skipped — billing not ready yet")
		return
	_plugin.queryProductDetails([PRODUCT_REVIVE_TOKENS], "inapp")

func _on_connected() -> void:
	is_ready = true
	print("BillingManager: billing client connected OK")
	billing_ready.emit()

func _on_connect_error(error_code: int, debug_message: String) -> void:
	push_error("BillingManager: connect_error %d — %s" % [error_code, debug_message])

func _on_product_details_query_completed(product_details: Array) -> void:
	if product_details.is_empty():
		push_error("BillingManager: product details query returned empty — check Play Console product ID")
		return
	_pending_product_details = product_details[0]
	_plugin.purchase(_pending_product_details)

func _on_product_details_query_error(error_code: int, debug_message: String, product_ids: Array) -> void:
	push_error("BillingManager: product query error %d — %s (ids: %s)" % [error_code, debug_message, str(product_ids)])
	purchase_failed.emit(PRODUCT_REVIVE_TOKENS)

func _on_purchases_updated(purchases: Array) -> void:
	for purchase in purchases:
		var ids: Array = purchase.get("productIds", [])
		if ids.has(PRODUCT_REVIVE_TOKENS):
			_plugin.acknowledgePurchase(purchase.get("purchaseToken", ""))
			purchase_succeeded.emit(PRODUCT_REVIVE_TOKENS, TOKENS_PER_PACK)
		else:
			purchase_failed.emit(ids[0] if not ids.is_empty() else "unknown")

func _on_purchase_error(error_code: int, debug_message: String) -> void:
	push_error("BillingManager: purchase_error %d — %s" % [error_code, debug_message])
	purchase_failed.emit(PRODUCT_REVIVE_TOKENS)
