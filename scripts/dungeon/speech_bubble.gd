class_name SpeechBubble
extends Node2D

# Issue #197: in-world speech bubble that floats above an NPC and renders an
# NPCOptionList as a vertical menu. Owned by InteractableNPC — the NPC opens
# the bubble on player attack press, hands it the option list and a
# BubbleSelectionController, and connects to option_confirmed to dispatch the
# chosen option's effect_id.
#
# The bubble itself is a Node2D so it lives in world space and naturally
# inherits the NPC's transform. The Control subtree (PanelContainer +
# VBoxContainer) renders the rows. Visual styling is intentionally minimal in
# this slice — the bubble's *wiring* (mounting, input routing, signals) is
# what tests cover; rendering polish is verified in QA (#200).
#
# Public surface used by InteractableNPC + tests:
#   open(list, controller)        — populate rows and arm input
#   move_next() / move_prev()     — proxy to the controller, refreshes UI
#   confirm()                     — proxy to the controller; emits option_confirmed
#                                   with the chosen option's effect_id
#   dismiss()                     — emits dismissed and removes self from tree

signal option_confirmed(effect_id: String)
signal dismissed()

# The bubble's bottom edge sits this many world px above the NPC's origin. The
# width is NOT fixed — it grows to fit the widest row (see _resize_to_content).
const BOTTOM_MARGIN := 32.0

# NPCs near the top of a room (e.g. the bartender's counter) push a
# tall/wide menu above the visible viewport, clipping the top rows (#197
# follow-up). After anchoring above the NPC, clamp the panel back into the
# active camera's visible rect with this screen-space margin.
const SCREEN_MARGIN := 8.0

var selection: BubbleSelectionController = null

var _list: NPCOptionList = null
var _row_labels: Array[Label] = []
var _row_enabled: Array[bool] = []
var _rows_container: VBoxContainer = null
var _panel: PanelContainer = null

# Issue #510: disabled/unaffordable rows render in red instead of the old
# flat-gray modulate. _refresh_highlight's yellow takes precedence when a
# disabled row happens to be the highlighted one.
const _DISABLED_COLOR := Color(1.0, 0.2, 0.2, 1.0)
const _HIGHLIGHT_COLOR := Color(1.0, 0.9, 0.2)


func _ready() -> void:
	_panel = get_node_or_null("Panel") as PanelContainer
	_rows_container = get_node_or_null("Panel/Rows") as VBoxContainer


# Populates the bubble with one row per option and arms input handling. The
# controller's initial cursor (which already skips leading disabled rows) is
# what we highlight first — no extra cursor logic lives in the UI.
func open(list: NPCOptionList, controller: BubbleSelectionController) -> void:
	_list = list
	selection = controller
	_rebuild_rows()
	_refresh_highlight()


func move_next() -> void:
	if selection == null:
		return
	selection.move_next()
	_refresh_highlight()


func move_prev() -> void:
	if selection == null:
		return
	selection.move_prev()
	_refresh_highlight()


# Returns the effect_id of the confirmed option (or "" if confirm was a no-op
# because the highlighted row is disabled / no options enabled). The bubble
# also emits option_confirmed when the effect_id is non-empty so the NPC's
# connected handler runs.
func confirm() -> String:
	if selection == null or _list == null:
		return ""
	var idx := selection.confirm()
	if idx < 0:
		return ""
	var opt: NPCOption = _list.get_at(idx)
	option_confirmed.emit(opt.effect_id)
	return opt.effect_id


func dismiss() -> void:
	dismissed.emit()
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	queue_free()


# Input is POLLED (Input.is_action_just_pressed) rather than read from
# _unhandled_input. On touch the joystick and attack button drive these actions
# via Input.action_press(), which updates polled state but emits no InputEvent —
# so an event handler navigates/confirms only on a desktop keyboard and is dead
# on a deployed phone. Polling matches the NPC base + chest_entity + player and
# works on both. The elif chain keeps a single press to one action per frame.
func _physics_process(_delta: float) -> void:
	if selection == null:
		return
	if Input.is_action_just_pressed("move_up"):
		move_prev()
	elif Input.is_action_just_pressed("move_down"):
		move_next()
	elif Input.is_action_just_pressed("attack"):
		# confirm() may dispatch an effect that dismisses this bubble (frees it),
		# so do nothing with self afterward — we return immediately.
		confirm()


func _rebuild_rows() -> void:
	if _rows_container == null:
		return
	for child in _rows_container.get_children():
		child.queue_free()
	_row_labels.clear()
	_row_enabled.clear()
	if _list == null:
		return
	for i in _list.size():
		var opt: NPCOption = _list.get_at(i)
		var lbl := Label.new()
		lbl.text = opt.label
		if opt.cost_currency == NPCOption.CurrencyType.GOLD:
			lbl.text += "  —  %d G" % opt.cost_amount
		var enabled := opt.is_enabled()
		if not enabled:
			lbl.add_theme_color_override("font_color", _DISABLED_COLOR)
		_rows_container.add_child(lbl)
		_row_labels.append(lbl)
		_row_enabled.append(enabled)
	_resize_to_content()


# The Panel is a free-floating Control under a Node2D, so no parent container
# lays it out — its scene offsets pinned it to a fixed 96px box that clipped
# longer labels like "Get a beer". Shrink-wrap it to the rows' combined minimum
# size, then centre it horizontally over the NPC with its bottom edge
# BOTTOM_MARGIN above the origin.
func _resize_to_content() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	var sz := _panel.size
	var local_pos := Vector2(-sz.x * 0.5, -BOTTOM_MARGIN - sz.y)
	_panel.position = _clamp_within_camera_view(local_pos, sz)


# Pulls the panel back inside the active camera's visible rect if anchoring
# above the NPC would push it off-screen. No-op when there's no active
# Camera2D (e.g. in unit tests), preserving the plain above-NPC position.
func _clamp_within_camera_view(local_pos: Vector2, sz: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return local_pos
	var camera := viewport.get_camera_2d()
	if camera == null:
		return local_pos
	var half_view := viewport.get_visible_rect().size * 0.5 / camera.zoom
	var view_center := camera.get_screen_center_position()
	var view_min := view_center - half_view
	var view_max := view_center + half_view
	var global_top_left := global_position + local_pos
	var clamped := global_top_left
	clamped.x = clampf(clamped.x, view_min.x + SCREEN_MARGIN, view_max.x - sz.x - SCREEN_MARGIN)
	clamped.y = clampf(clamped.y, view_min.y + SCREEN_MARGIN, view_max.y - sz.y - SCREEN_MARGIN)
	return clamped - global_position


func _refresh_highlight() -> void:
	var idx := -1
	if selection != null:
		idx = selection.current_index()
	for i in _row_labels.size():
		var lbl := _row_labels[i]
		if i == idx:
			lbl.add_theme_color_override("font_color", _HIGHLIGHT_COLOR)
		elif not _row_enabled[i]:
			lbl.add_theme_color_override("font_color", _DISABLED_COLOR)
		else:
			lbl.remove_theme_color_override("font_color")
