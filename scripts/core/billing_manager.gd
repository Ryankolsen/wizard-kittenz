extends Node

# Two-backend facade over platform in-app-purchase plugins (#403). Detects
# whichever platform billing singleton is present at runtime — Google Play
# on Android, Apple StoreKit on iOS — and normalizes it behind a single
# public interface so ShopScreen / PurchaseGrantHandler / PurchaseRegistry
# never need to know which platform they're running on.
#
# On desktop / GUT neither singleton exists, so _backend stays null and
# every public method is a no-op (with a warning), same as before the
# facade split.

signal billing_ready()
signal purchase_succeeded(product_id: String)
signal purchase_failed(product_id: String)

var is_ready := false

var _backend = null
var _poll_timer: Timer

# How often to drain the Apple backend's event queue (see poll() on
# AppleStoreKitBackend — that plugin has no signals, only a pending-event
# queue). Cheap no-op on the Google backend, so one timer serves both.
const POLL_INTERVAL_SECONDS := 0.25

func _ready() -> void:
	if Engine.has_singleton("GodotGooglePlayBilling"):
		_backend = GooglePlayBillingBackend.new(Engine.get_singleton("GodotGooglePlayBilling"))
	elif Engine.has_singleton("InAppStore"):
		_backend = AppleStoreKitBackend.new(Engine.get_singleton("InAppStore"))
	else:
		push_warning("BillingManager: no platform billing singleton available (not an Android or iOS build)")
		return
	_wire_backend()
	_backend.start()
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_SECONDS
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(func() -> void: _backend.poll())
	add_child(_poll_timer)

# Connects a backend's normalized signals to BillingManager's own. Split out
# from _ready() so tests can inject a fake backend double and wire it up
# without a real platform singleton.
func _wire_backend() -> void:
	_backend.ready.connect(_on_backend_ready)
	_backend.purchase_succeeded.connect(func(product_id: String) -> void: purchase_succeeded.emit(product_id))
	_backend.purchase_failed.connect(func(product_id: String) -> void: purchase_failed.emit(product_id))

func _on_backend_ready() -> void:
	is_ready = true
	billing_ready.emit()

# Single entry point for all IAP, regardless of backend.
func start_purchase(product_id: String) -> void:
	if _backend == null or not is_ready:
		push_warning("BillingManager: purchase skipped — billing not ready")
		return
	_backend.start_purchase(product_id)
