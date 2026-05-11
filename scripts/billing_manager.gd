extends Node

# Wraps the GodotGooglePlayBilling 3.x addon (PBL 8.3.0).
# Uses the raw JNI singleton so no class_name dependency on the addon being enabled.
# On desktop/test builds the plugin singleton is absent — all methods degrade gracefully.
#
# Product-specific purchase flow lives in slice 4 (#31). This shell keeps the
# plugin connection alive so later slices can plug in queries + purchases
# without re-walking the addon-availability gauntlet.

signal billing_ready()

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
	_plugin.startConnection()

func _on_connected() -> void:
	is_ready = true
	print("BillingManager: billing client connected OK")
	billing_ready.emit()

func _on_connect_error(response_code: int, debug_message: String) -> void:
	push_error("BillingManager: connect_error %d — %s" % [response_code, debug_message])
