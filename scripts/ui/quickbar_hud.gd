class_name QuickbarHUD
extends Control

# Slice 3 of PRD #210. View-only 2×2 grid of Control controls bound
# to the local player's Quickbar. Polls per-slot derived state each frame
# (cooldown remaining and MP availability change continuously), repaints on
# Quickbar.slot_changed, and pulses a fire highlight on
# QuickbarController.slot_fired. Tap dispatch is the controller's job — the
# HUD only sets visual state and routes touch presses to the cast_slot_N
# InputMap actions via Control.
#
# Empty-slot taps signal up to open the Skills tab (PRD §User story 19).
# The HUD looks up the PauseMenu lazily via /root/GameState's hud / pause
# wiring; if neither is reachable (headless tests) the signal still fires
# for inspection.

const ControlsSettings := preload("res://scripts/core/controls_settings_manager.gd")
const SlotViewScript := preload("res://scripts/ui/quickbar_slot_view.gd")
const _QuickbarScript := preload("res://scripts/character/quickbar.gd")
const _QuickbarSlotStateScript := preload("res://scripts/ui/quickbar_slot_state.gd")

const SLOT_SIZE: float = 28.0
const SLOT_SPACING: float = 4.0

signal empty_slot_pressed(slot: int)

var _player = null
var _quickbar = null
var _controller = null
var _slots: Array = []
var _tooltip: Label = null

func _ready() -> void:
	_ensure_slot_views()
	_ensure_tooltip()
	_layout_slots()
	_bind_player()

func _process(_dt: float) -> void:
	if _player == null or _quickbar == null:
		_bind_player()
		if _quickbar == null:
			return
	_refresh_all_slots()

func bind_player(player) -> void:
	# Test-friendly seam: allow injecting a player without _find_player walking
	# get_tree groups.
	_player = player
	_quickbar = null
	_controller = null
	_bind_player_internal(false)

func _bind_player() -> void:
	if _player == null:
		_player = _find_player()
	_bind_player_internal(true)

func _bind_player_internal(allow_skip_when_already_bound: bool) -> void:
	if _player == null:
		return
	if allow_skip_when_already_bound and _quickbar != null:
		return
	if _player.has_method("get_quickbar"):
		_quickbar = _player.get_quickbar()
	if _player.has_method("get_quickbar_controller"):
		_controller = _player.get_quickbar_controller()
	elif "_quickbar_controller" in _player:
		_controller = _player._quickbar_controller
	if _quickbar != null and _quickbar.has_signal("slot_changed"):
		if not _quickbar.slot_changed.is_connected(_on_slot_changed):
			_quickbar.slot_changed.connect(_on_slot_changed)
	if _controller != null and _controller.has_signal("slot_fired"):
		if not _controller.slot_fired.is_connected(_on_slot_fired):
			_controller.slot_fired.connect(_on_slot_fired)

func _find_player():
	var tree := get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("player"):
		return n
	return null

func _ensure_slot_views() -> void:
	if _slots.size() == _QuickbarScript.SLOT_COUNT:
		return
	_slots.clear()
	for i in range(1, _QuickbarScript.SLOT_COUNT + 1):
		var existing := get_node_or_null("Slot%d" % i) as Control
		if existing != null and existing is Control:
			_slots.append(existing)
			_wire_slot_signals(existing)
			continue
		var v: Control = SlotViewScript.new()
		v.name = "Slot%d" % i
		v.slot_index = i
		v.action_name = StringName("cast_slot_%d" % i)
		add_child(v)
		_wire_slot_signals(v)
		_slots.append(v)

func _wire_slot_signals(v: Control) -> void:
	if not v.empty_slot_pressed.is_connected(_on_empty_slot_pressed):
		v.empty_slot_pressed.connect(_on_empty_slot_pressed)

func _ensure_tooltip() -> void:
	_tooltip = get_node_or_null("Tooltip") as Label
	if _tooltip != null:
		return
	_tooltip = Label.new()
	_tooltip.name = "Tooltip"
	_tooltip.visible = false
	_tooltip.add_theme_font_size_override("font_size", 10)
	_tooltip.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	add_child(_tooltip)

# Public so TouchControls / HUD can flip layout in response to a settings
# change without re-instancing the scene. Computes 2×2 absolute offsets
# from the QuickbarHUD's own (0,0); the parent scene positions us.
func _layout_slots() -> void:
	for i in range(_slots.size()):
		var col := i % 2
		var row := i / 2
		var v: Control = _slots[i]
		v.position = Vector2(col * (SLOT_SIZE + SLOT_SPACING), row * (SLOT_SIZE + SLOT_SPACING))
		# custom_minimum_size first — the slot view's _ready sets a default
		# minimum that would otherwise clamp v.size back up.
		v.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		v.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var w := 2.0 * SLOT_SIZE + SLOT_SPACING
	var h := 2.0 * SLOT_SIZE + SLOT_SPACING
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)

func _refresh_all_slots() -> void:
	if _quickbar == null:
		return
	var caster = null
	if _player != null and "data" in _player:
		caster = _player.data
	for i in range(1, _QuickbarScript.SLOT_COUNT + 1):
		var spell: Spell = _quickbar.get_slot(i)
		var state := _QuickbarSlotStateScript.derive(spell, caster)
		var v: Control = _slots[i - 1]
		v.set_spell_and_state(spell, state)

func _on_slot_changed(_n: int) -> void:
	_refresh_all_slots()

func _on_slot_fired(n: int) -> void:
	if n < 1 or n > _slots.size():
		return
	(_slots[n - 1] as Control).play_fire_highlight()

func _on_empty_slot_pressed(n: int) -> void:
	emit_signal("empty_slot_pressed", n)
	_open_skills_tab()

# Opens the pause menu's Skills tab. Walks the HUD CanvasLayer to find the
# existing PauseMenu (lazy-instanced by HUD) — falls through silently when
# we're not under a HUD (test harness / standalone). Avoids importing HUD
# or PauseMenu directly so the dependency stays one-way (HUD owns
# QuickbarHUD, not the reverse).
func _open_skills_tab() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud = _find_hud()
	if hud == null:
		return
	if not hud.has_method("_ensure_pause_menu"):
		return
	var menu = hud._ensure_pause_menu()
	if menu != null and menu.has_method("open_skills_panel"):
		menu.open_skills_panel()

func _find_hud():
	var n := get_parent()
	while n != null:
		if n is HUD:
			return n
		n = n.get_parent()
	return null
