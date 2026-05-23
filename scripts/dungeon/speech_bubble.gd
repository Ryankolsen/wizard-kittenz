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

var selection: BubbleSelectionController = null

var _list: NPCOptionList = null
var _row_labels: Array[Label] = []
var _rows_container: VBoxContainer = null


func _ready() -> void:
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
	var opt: NPCOption = _list.get(idx)
	option_confirmed.emit(opt.effect_id)
	return opt.effect_id


func dismiss() -> void:
	dismissed.emit()
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if selection == null:
		return
	if event.is_action_pressed("move_up"):
		move_prev()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		move_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		confirm()
		get_viewport().set_input_as_handled()


func _rebuild_rows() -> void:
	if _rows_container == null:
		return
	for child in _rows_container.get_children():
		child.queue_free()
	_row_labels.clear()
	if _list == null:
		return
	for i in _list.size():
		var opt: NPCOption = _list.get(i)
		var lbl := Label.new()
		lbl.text = opt.label
		if not opt.is_enabled():
			lbl.modulate = Color(0.5, 0.5, 0.5, 1.0)
		_rows_container.add_child(lbl)
		_row_labels.append(lbl)


func _refresh_highlight() -> void:
	var idx := -1
	if selection != null:
		idx = selection.current_index()
	for i in _row_labels.size():
		var lbl := _row_labels[i]
		if i == idx:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			lbl.remove_theme_color_override("font_color")
