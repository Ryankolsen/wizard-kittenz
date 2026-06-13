class_name PotionBeltHUD
extends Control

# Slice 8 of PRD #358. View-only 1×3 strip bound to the local player's
# PotionBelt + ConsumableInventory. Polls per-slot render state each frame
# (shared cooldown drains continuously, inventory counts change asynchronously),
# repaints on belt.slot_changed / inventory.inventory_changed, and pulses a
# fire highlight on belt.slot_used.
#
# Unlike QuickbarHUD, the HUD itself owns:
#   - the per-frame belt.tick(delta) drain (PotionBelt is pure data; nothing
#     else holds it)
#   - the use_potion_1..3 InputMap polling (no separate PotionBeltController
#     node — the dispatch is simpler than QuickbarController's spell+caster
#     gating, just three lines of forwarding into belt.use_slot)

const SlotViewScript := preload("res://scripts/ui/potion_belt_slot_view.gd")

const SLOT_SIZE: float = 28.0
const SLOT_SPACING: float = 4.0

signal slot_used(slot: int)

var _player = null
var _belt: PotionBelt = null
var _inventory: ConsumableInventory = null
var _caster = null
var _slots: Array = []

func _ready() -> void:
	_ensure_slot_views()
	_layout_slots()
	_bind_player()

func _process(dt: float) -> void:
	if _belt == null:
		_bind_player()
		if _belt == null:
			return
	_belt.tick(dt)
	_poll_inputs()
	_refresh_all_slots()

# Test-friendly seam: inject the belt/inventory/caster triple directly without
# walking get_tree groups for a player node.
func bind(belt: PotionBelt, inventory: ConsumableInventory, caster) -> void:
	_player = null
	_belt = belt
	_inventory = inventory
	_caster = caster
	_wire_data_signals()

# Game-path seam: pull belt + inventory off a Player (which itself reads them
# off GameState). Mirrors QuickbarHUD.bind_player so the HUD parent doesn't
# need to know which autoload owns the data.
func bind_player(player) -> void:
	_player = player
	_belt = null
	_inventory = null
	_bind_player_internal(false)

func _bind_player() -> void:
	if _player == null:
		_player = _find_player()
	_bind_player_internal(true)

func _bind_player_internal(allow_skip_when_already_bound: bool) -> void:
	if _player == null:
		return
	if allow_skip_when_already_bound and _belt != null:
		return
	if _player.has_method("get_potion_belt"):
		_belt = _player.get_potion_belt()
	if _player.has_method("get_consumable_inventory"):
		_inventory = _player.get_consumable_inventory()
	if "data" in _player:
		_caster = _player.data
	_wire_data_signals()

func _wire_data_signals() -> void:
	if _belt != null:
		if _belt.has_signal("slot_changed") and not _belt.slot_changed.is_connected(_on_slot_changed):
			_belt.slot_changed.connect(_on_slot_changed)
		if _belt.has_signal("slot_used") and not _belt.slot_used.is_connected(_on_slot_used):
			_belt.slot_used.connect(_on_slot_used)
	if _inventory != null:
		if _inventory.has_signal("inventory_changed") and not _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.connect(_on_inventory_changed)

func _find_player():
	var tree := get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("player"):
		return n
	return null

func _ensure_slot_views() -> void:
	if _slots.size() == PotionBelt.SLOT_COUNT:
		return
	_slots.clear()
	for i in range(1, PotionBelt.SLOT_COUNT + 1):
		var existing := get_node_or_null("Slot%d" % i) as Control
		if existing != null and existing is Control:
			_slots.append(existing)
			continue
		var v: Control = SlotViewScript.new()
		v.name = "Slot%d" % i
		v.slot_index = i
		v.action_name = StringName("use_potion_%d" % i)
		add_child(v)
		_slots.append(v)

# Horizontal 1×3 strip. Parent scene positions the whole HUD; we lay out the
# three slots from (0,0) rightward.
func _layout_slots() -> void:
	for i in range(_slots.size()):
		var v: Control = _slots[i]
		v.position = Vector2(i * (SLOT_SIZE + SLOT_SPACING), 0)
		# custom_minimum_size first so the slot view's _ready default doesn't
		# clamp v.size back up.
		v.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		v.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var w := PotionBelt.SLOT_COUNT * SLOT_SIZE + (PotionBelt.SLOT_COUNT - 1) * SLOT_SPACING
	custom_minimum_size = Vector2(w, SLOT_SIZE)
	size = Vector2(w, SLOT_SIZE)

# Pure mapping: returns 1..SLOT_COUNT for a recognized use_potion_N action,
# else 0. Pulled out as a static so a test can pin the routing without driving
# Input.is_action_just_pressed (which has frame-scoped semantics that don't
# reset inside a synchronous test body). Parallel to the cast_slot_N polling
# in QuickbarController.
static func slot_for_action(action_name: StringName) -> int:
	for i in range(1, PotionBelt.SLOT_COUNT + 1):
		if action_name == StringName("use_potion_%d" % i):
			return i
	return 0

func _poll_inputs() -> void:
	for i in range(1, PotionBelt.SLOT_COUNT + 1):
		if Input.is_action_just_pressed("use_potion_%d" % i):
			try_use_slot(i)

# Public dispatch entry point. Returns true only when the belt actually fired
# (consumed a potion + applied the effect). slot_used is re-emitted only on
# that success path so downstream visuals don't churn on the harmless-mis-tap
# cases PotionBelt already gates.
func try_use_slot(n: int) -> bool:
	if _belt == null:
		return false
	if not _belt.use_slot(n, _caster, _inventory):
		return false
	slot_used.emit(n)
	return true

func _refresh_all_slots() -> void:
	if _belt == null:
		return
	var fraction := 0.0
	if PotionBelt.COOLDOWN_SECONDS > 0.0:
		fraction = _belt.cooldown_remaining() / PotionBelt.COOLDOWN_SECONDS
	for i in range(1, PotionBelt.SLOT_COUNT + 1):
		var pid: String = _belt.get_slot(i)
		var def: PotionDefinition = null
		var count := 0
		if pid != "":
			def = PotionCatalog.find(pid)
			if _inventory != null:
				count = _inventory.count_of(pid)
		var state := PotionSlotState.derive(def, count, fraction)
		_slots[i - 1].set_potion_and_state(def, state)

func _on_slot_changed(_n: int) -> void:
	_refresh_all_slots()

func _on_inventory_changed() -> void:
	_refresh_all_slots()

func _on_slot_used(n: int) -> void:
	if n < 1 or n > _slots.size():
		return
	(_slots[n - 1] as Control).play_fire_highlight()
