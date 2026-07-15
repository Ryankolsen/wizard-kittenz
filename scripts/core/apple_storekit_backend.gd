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

# gem_bundle_hero was accidentally created and deleted in App Store Connect
# before this backend shipped; Apple permanently reserves deleted product
# IDs, so the App Store product had to be recreated under a different ID.
# PurchaseRegistry.GEM_BUNDLE_HERO stays "gem_bundle_hero" everywhere else
# (it's already live on Google Play) — only this backend needs to know about
# the App-Store-specific ID.
const _APPLE_PRODUCT_ID_OVERRIDES := {
	"gem_bundle_hero": "gem_bundle_hero_ios",
}

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
	var apple_id := _to_apple_id(product_id)
	var err: int = _plugin.request_product_info({"product_ids": PackedStringArray([apple_id])})
	if err != OK:
		push_error("BillingManager: Apple request_product_info error %d for %s" % [err, product_id])
		_pending_product_id = ""
		purchase_failed.emit(product_id)

# Maps our canonical PurchaseRegistry product id to the id actually
# registered in App Store Connect (see _APPLE_PRODUCT_ID_OVERRIDES).
func _to_apple_id(product_id: String) -> String:
	return _APPLE_PRODUCT_ID_OVERRIDES.get(product_id, product_id)

# Reverse of _to_apple_id — event payloads from the plugin carry the App
# Store id, but callers of this backend expect the canonical id back.
func _from_apple_id(apple_id: String) -> String:
	for canonical_id: String in _APPLE_PRODUCT_ID_OVERRIDES:
		if _APPLE_PRODUCT_ID_OVERRIDES[canonical_id] == apple_id:
			return canonical_id
	return apple_id

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
	var apple_id := _to_apple_id(product_id)
	var invalid_ids: Array = event.get("invalid_ids", [])
	if invalid_ids.has(apple_id):
		push_error("BillingManager: Apple product id invalid: %s — check App Store Connect product ID" % apple_id)
		_pending_product_id = ""
		purchase_failed.emit(product_id)
		return
	_pending_product_id = ""
	var err: int = _plugin.purchase({"product_id": apple_id})
	if err != OK:
		push_error("BillingManager: Apple purchase launch error %d for %s" % [err, product_id])
		purchase_failed.emit(product_id)

func _on_purchase(event: Dictionary) -> void:
	var result := String(event.get("result", ""))
	var apple_id := String(event.get("product_id", ""))
	var product_id := _from_apple_id(apple_id)
	if result == "ok":
		if apple_id != "":
			_plugin.finish_transaction(apple_id)
		purchase_succeeded.emit(product_id)
	elif result == "error":
		push_error("BillingManager: Apple purchase error for %s" % product_id)
		purchase_failed.emit(product_id)
	# "progress" — purchase still in flight (e.g. Ask to Buy); wait for a
	# later "ok"/"error" event rather than resolving here.

func _on_restore(event: Dictionary) -> void:
	var result := String(event.get("result", ""))
	var apple_id := String(event.get("product_id", ""))
	if result == "ok" and apple_id != "":
		_plugin.finish_transaction(apple_id)
		purchase_succeeded.emit(_from_apple_id(apple_id))
