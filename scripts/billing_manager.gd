extends Node

# Wraps the GodotGooglePlayBilling 3.x addon (PBL 8.3.0).
# Uses the raw JNI singleton so no class_name dependency on the addon being enabled.
# On desktop/test builds the plugin singleton is absent — all methods degrade gracefully.

const PRODUCT_REVIVE_TOKENS := "revive_token_pack_5"
const TOKENS_PER_PACK := 5

signal billing_ready()
signal purchase_succeeded(product_id: String, tokens: int)
signal purchase_failed(product_id: String)

var is_ready := false

var _plugin = null

func _ready() -> void:
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		push_warning("BillingManager: GodotGooglePlayBilling not available (not an Android build)")
		return
	_plugin = Engine.get_singleton("GodotGooglePlayBilling")
	_plugin.initPlugin()
	_plugin.connected.connect(_on_connected)
	_plugin.connect_error.connect(_on_connect_error)
	_plugin.query_product_details_response.connect(_on_query_product_details_response)
	_plugin.on_purchase_updated.connect(_on_purchase_updated)
	_plugin.startConnection()

func start_purchase_revive_tokens() -> void:
	if _plugin == null or not is_ready:
		push_warning("BillingManager: purchase skipped — billing not ready")
		return
	_plugin.queryProductDetails(PackedStringArray([PRODUCT_REVIVE_TOKENS]), "inapp")

func _on_connected() -> void:
	is_ready = true
	print("BillingManager: billing client connected OK")
	billing_ready.emit()

func _on_connect_error(response_code: int, debug_message: String) -> void:
	push_error("BillingManager: connect_error %d — %s" % [response_code, debug_message])

func _on_query_product_details_response(result: Dictionary) -> void:
	if result.response_code != 0:  # 0 = BillingResponseCode.OK
		push_error("BillingManager: product query error %d — %s" % [result.response_code, result.debug_message])
		purchase_failed.emit(PRODUCT_REVIVE_TOKENS)
		return
	if result.product_details.is_empty():
		push_error("BillingManager: product details empty — check Play Console product ID")
		purchase_failed.emit(PRODUCT_REVIVE_TOKENS)
		return
	var res: Dictionary = _plugin.purchase(PRODUCT_REVIVE_TOKENS, "", "", false)
	if res.get("response_code", -1) != 0:
		push_error("BillingManager: purchase launch error %d — %s" % [res.get("response_code", -1), res.get("debug_message", "")])
		purchase_failed.emit(PRODUCT_REVIVE_TOKENS)

func _on_purchase_updated(result: Dictionary) -> void:
	if result.response_code != 0:
		push_error("BillingManager: purchase error %d — %s" % [result.response_code, result.debug_message])
		purchase_failed.emit(PRODUCT_REVIVE_TOKENS)
		return
	for purchase in result.purchases:
		if purchase.product_ids.has(PRODUCT_REVIVE_TOKENS):
			_plugin.consumePurchase(purchase.purchase_token)
			purchase_succeeded.emit(PRODUCT_REVIVE_TOKENS, TOKENS_PER_PACK)
		else:
			var id: String = purchase.product_ids[0] if not purchase.product_ids.is_empty() else "unknown"
			purchase_failed.emit(id)
