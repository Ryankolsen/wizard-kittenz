extends Node

# Wraps the GodotGooglePlayBilling 3.x addon (PBL 8.3.0) for non-consumable
# IAP only — no consumable products in the catalog any more (the revive-token
# pack was removed in slice 2 of the monetization pivot, #30). Non-consumables
# require acknowledgePurchase rather than consumePurchase, and the purchase
# flow must be idempotent: a player who already owns the item should not be
# able to double-grant by re-running the purchase.
#
# Flow:
#   start_purchase(id)
#     -> queryProductDetails([id], "inapp")
#     -> on query_product_details_response, plugin.purchase(id, ...)
#     -> on on_purchase_updated, acknowledgePurchase(token), emit purchase_succeeded(id)
#
# On billing connect, queryPurchases("inapp") restores any prior purchases
# whose acknowledgement was never recorded (reinstall / device change). The
# grant handler (#32) listens to purchase_succeeded and is responsible for
# deduping replays — server-side acknowledgement is itself idempotent.
#
# On desktop / GUT the GodotGooglePlayBilling JNI singleton is absent and
# every public method is a no-op (with a warning) so call sites work the
# same on every platform.

signal billing_ready()
signal purchase_succeeded(product_id: String)
signal purchase_failed(product_id: String)

var is_ready := false

var _plugin = null
# The product currently mid-flight through queryProductDetails. The plugin
# response carries the product list back so this would be redundant if we
# only purchased one product at a time per session — but holding it lets us
# fail loudly if the response shape ever drifts.
var _pending_query: String = ""

func _ready() -> void:
	if not Engine.has_singleton("GodotGooglePlayBilling"):
		push_warning("BillingManager: GodotGooglePlayBilling not available (not an Android build)")
		return
	_plugin = Engine.get_singleton("GodotGooglePlayBilling")
	_plugin.initPlugin()
	_plugin.connected.connect(_on_connected)
	_plugin.connect_error.connect(_on_connect_error)
	_plugin.query_product_details_response.connect(_on_query_product_details_response)
	_plugin.query_purchases_response.connect(_on_query_purchases_response)
	_plugin.on_purchase_updated.connect(_on_purchase_updated)
	_plugin.acknowledge_purchase_response.connect(_on_acknowledge_purchase_response)
	_plugin.startConnection()

# Single entry point for all IAP. The plugin requires the product to be
# cached in its internal store before purchase() can launch the billing UI,
# so we always go through queryProductDetails first — even if the catalog
# was queried at startup, individual purchase intents must re-resolve.
func start_purchase(product_id: String) -> void:
	if _plugin == null or not is_ready:
		push_warning("BillingManager: purchase skipped — billing not ready")
		return
	_pending_query = product_id
	_plugin.queryProductDetails(PackedStringArray([product_id]), "inapp")

func _on_connected() -> void:
	is_ready = true
	print("BillingManager: billing client connected OK")
	billing_ready.emit()
	# Restore any unacknowledged non-consumables (reinstall / device change).
	# The grant handler dedupes replays; here we only need to surface them.
	_plugin.queryPurchases("inapp", false)

func _on_connect_error(response_code: int, debug_message: String) -> void:
	push_error("BillingManager: connect_error %d — %s" % [response_code, debug_message])

func _on_query_product_details_response(result: Dictionary) -> void:
	var product_id := _pending_query
	_pending_query = ""
	if int(result.get("response_code", -1)) != 0:
		push_error("BillingManager: product query error %d — %s" % [
			int(result.get("response_code", -1)), str(result.get("debug_message", ""))])
		purchase_failed.emit(product_id)
		return
	var product_details: Array = result.get("product_details", [])
	if product_details.is_empty():
		push_error("BillingManager: product details empty for %s — check Play Console product ID" % product_id)
		purchase_failed.emit(product_id)
		return
	var res: Dictionary = _plugin.purchase(product_id, "", "", false)
	if int(res.get("response_code", -1)) != 0:
		push_error("BillingManager: purchase launch error %d — %s" % [
			int(res.get("response_code", -1)), str(res.get("debug_message", ""))])
		purchase_failed.emit(product_id)

func _on_purchase_updated(result: Dictionary) -> void:
	if int(result.get("response_code", -1)) != 0:
		push_error("BillingManager: purchase error %d — %s" % [
			int(result.get("response_code", -1)), str(result.get("debug_message", ""))])
		# The error response doesn't include product IDs; emit a blank product
		# so the UI can dismiss its "purchase pending" spinner without needing
		# to know which one failed.
		purchase_failed.emit("")
		return
	for purchase in result.get("purchases", []):
		_handle_completed_purchase(purchase)

# Restore-from-server: same purchase shape as on_purchase_updated, but fired
# at billing-ready time for items the player already owns from a previous
# install. Acknowledge anything the store thinks is unacknowledged and
# re-emit purchase_succeeded so the grant handler can no-op or restore as
# appropriate.
func _on_query_purchases_response(result: Dictionary) -> void:
	if int(result.get("response_code", -1)) != 0:
		push_warning("BillingManager: query_purchases error %d — %s" % [
			int(result.get("response_code", -1)), str(result.get("debug_message", ""))])
		return
	for purchase in result.get("purchases", []):
		_handle_completed_purchase(purchase)

func _handle_completed_purchase(purchase: Dictionary) -> void:
	var product_ids: Array = purchase.get("product_ids", [])
	if product_ids.is_empty():
		return
	var product_id: String = product_ids[0]
	# Skip already-acknowledged purchases. Re-acknowledging is a no-op on
	# the server but generates spurious BILLING_RESPONSE errors in logcat.
	if not bool(purchase.get("is_acknowledged", false)):
		_plugin.acknowledgePurchase(str(purchase.get("purchase_token", "")))
	purchase_succeeded.emit(product_id)

func _on_acknowledge_purchase_response(result: Dictionary) -> void:
	if int(result.get("response_code", -1)) != 0:
		push_error("BillingManager: acknowledge_purchase error %d — %s" % [
			int(result.get("response_code", -1)), str(result.get("debug_message", ""))])
