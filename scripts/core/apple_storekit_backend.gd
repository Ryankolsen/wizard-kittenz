class_name AppleStoreKitBackend
extends RefCounted

# Wraps an Apple StoreKit-backed Godot iOS plugin singleton (the "InAppStore"
# plugin from godot-ios-plugins, added under addons/ alongside
# GodotGooglePlayBilling in #402). All four Gem Bundle products are
# Consumable on both stores (#401), so unlike the Google adapter there is no
# separate acknowledge step — StoreKit finishes consumable transactions once
# the plugin reports a successful purchase.
#
# Assumed plugin surface (verified against the real singleton during the
# on-device work in #402/#406, since no iOS plugin binary is available in
# this environment to test against):
#   purchase(product_id: String)
#   signal product_purchased(product_id: String)
#   signal product_purchase_error(product_id: String, error: String)

signal ready()
signal purchase_succeeded(product_id: String)
signal purchase_failed(product_id: String)

var _plugin

func _init(plugin) -> void:
	_plugin = plugin

func start() -> void:
	_plugin.product_purchased.connect(_on_product_purchased)
	_plugin.product_purchase_error.connect(_on_product_purchase_error)
	ready.emit()

func start_purchase(product_id: String) -> void:
	_plugin.purchase(product_id)

func _on_product_purchased(product_id: String) -> void:
	purchase_succeeded.emit(product_id)

func _on_product_purchase_error(product_id: String, error: String) -> void:
	push_error("BillingManager: Apple purchase error for %s — %s" % [product_id, error])
	purchase_failed.emit(product_id)
