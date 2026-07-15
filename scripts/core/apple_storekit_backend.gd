class_name AppleStoreKitBackend
extends RefCounted

# Wraps the "InAppStore" plugin from godotengine/godot-ios-plugins (added
# under addons/ alongside GodotGooglePlayBilling per #402). All four Gem
# Bundle products are Consumable on both stores (#401), so unlike the Google
# adapter finish_transaction() is called ourselves once a purchase event
# reports "ok" rather than relying on the plugin's auto-finish option —
# mirrors GooglePlayBillingBackend only acknowledging after it has actually
# observed a completed purchase.
#
# Unlike GodotGooglePlayBilling, this plugin has no signals at all: it is a
# poll-based event queue (get_pending_event_count / pop_pending_event), so
# BillingManager must call poll() on a timer. Verified against the plugin's
# real source (plugins/inappstore/in_app_store.h, README.md) in
# godotengine/godot-ios-plugins — the previous version of this file described
# a signal-based surface (purchase(product_id), product_purchased /
# product_purchase_error signals) that does not exist on the real plugin and
# would have failed on first on-device purchase attempt.
#
# Real plugin surface:
#   request_product_info(Dictionary{"product_ids": PackedStringArray}) -> Error
#   purchase(Dictionary{"product_id": String}) -> Error
#   restore_purchases() -> Error
#   set_auto_finish_transaction(bool)
#   finish_transaction(product_id: String)
#   get_pending_event_count() -> int
#   pop_pending_event() -> Dictionary
#     {result: "ok"|"progress"|"error"|"unhandled"|"completed", type: "product_info"|"purchase"|"restore"|"completed", product_id, invalid_ids, ...}

signal ready()
signal purchase_succeeded(product_id: String)
signal purchase_failed(product_id: String)

var _plugin

# The product currently mid-flight through request_product_info. Mirrors
# GooglePlayBillingBackend._pending_query — the plugin always resolves one
# outstanding product_info request at a time per start_purchase() call.
var _pending_product_id: String = ""

func _init(plugin) -> void:
	_plugin = plugin

func start() -> void:
	# No "connected" callback exists on this plugin — the singleton is usable
	# as soon as it is present, so we go ready immediately.
	_plugin.set_auto_finish_transaction(false)
	# Restore any prior purchases (reinstall / device change). The grant
	# handler dedupes replays; we only need to surface them via poll().
	_plugin.restore_purchases()
	ready.emit()

# Single entry point for all IAP. The plugin requires product info to be
# fetched before purchase() can be launched, so we always resolve it first —
# even if the catalog was queried at startup, individual purchase intents
# must re-resolve (same rationale as the Google backend).
func start_purchase(product_id: String) -> void:
	_pending_product_id = product_id
	var err: int = _plugin.request_product_info({"product_ids": PackedStringArray([product_id])})
	if err != OK:
		push_error("BillingManager: Apple request_product_info error %d for %s" % [err, product_id])
		_pending_product_id = ""
		purchase_failed.emit(product_id)

# BillingManager must call this on a repeating timer — this plugin has no
# signals and only ever reports results through this queue.
func poll() -> void:
	while _plugin.get_pending_event_count() > 0:
		_handle_event(_plugin.pop_pending_event())

func _handle_event(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"product_info":
			_on_product_info(event)
		"purchase":
			_on_purchase(event)
		"restore":
			_on_restore(event)
		# "completed" marks the end of a restore stream; nothing to do.

func _on_product_info(event: Dictionary) -> void:
	var product_id := _pending_product_id
	var result := String(event.get("result", ""))
	if result != "ok":
		push_error("BillingManager: Apple product query error for %s — %s" % [product_id, result])
		_pending_product_id = ""
		purchase_failed.emit(product_id)
		return
	var invalid_ids: Array = event.get("invalid_ids", [])
	if invalid_ids.has(product_id):
		push_error("BillingManager: Apple product id invalid: %s — check App Store Connect product ID" % product_id)
		_pending_product_id = ""
		purchase_failed.emit(product_id)
		return
	_pending_product_id = ""
	var err: int = _plugin.purchase({"product_id": product_id})
	if err != OK:
		push_error("BillingManager: Apple purchase launch error %d for %s" % [err, product_id])
		purchase_failed.emit(product_id)

func _on_purchase(event: Dictionary) -> void:
	var result := String(event.get("result", ""))
	var product_id := String(event.get("product_id", ""))
	if result == "ok":
		if product_id != "":
			_plugin.finish_transaction(product_id)
		purchase_succeeded.emit(product_id)
	elif result == "error":
		push_error("BillingManager: Apple purchase error for %s" % product_id)
		purchase_failed.emit(product_id)
	# "progress" — purchase still in flight (e.g. Ask to Buy); wait for a
	# later "ok"/"error" event rather than resolving here.

func _on_restore(event: Dictionary) -> void:
	var result := String(event.get("result", ""))
	var product_id := String(event.get("product_id", ""))
	if result == "ok" and product_id != "":
		_plugin.finish_transaction(product_id)
		purchase_succeeded.emit(product_id)
