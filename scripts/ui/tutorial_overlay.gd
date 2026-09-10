class_name TutorialOverlay
extends CanvasLayer

# Generic, data-driven tutorial step renderer (PRD #596, issue #601). Renders
# any topic's step list (TutorialCatalog.steps_for) one step at a time: a
# highlight box around the resolved target control, or a plain centered text
# bubble when the step has no target_group (or its group resolves to nothing
# in the current scene). Mirrors PauseMenu's CanvasLayer + PROCESS_MODE_ALWAYS
# + get_tree().paused shape.
#
# This scene owns no sequencing/persistence knowledge — it doesn't call
# TutorialProgress.mark_seen or know about TutorialTrigger. The caller (a
# later wiring slice) listens for `finished` and marks the topic seen.
#
# Per-step "X" (CloseButton) advances to the next step — it dismisses only
# the current step's bubble, not the whole topic. "Skip" is the only way to
# abandon the remaining steps early. Both paths that end the topic (running
# off the end of the step list, or Skip) emit `finished` exactly once.

signal step_shown(topic_id: String, step_index: int)
signal finished(topic_id: String)

var _topic_id: String = ""
var _steps: Array[Dictionary] = []
var _step_index: int = 0
# Tracks whether *this* open() call paused the tree, so close() only
# unpauses when it owns that state — a should_pause=false caller (issue
# #608) must never stomp a pause some other system is holding.
var _paused_on_open: bool = false

const _HIGHLIGHT_PADDING := 6.0

func _ready() -> void:
	visible = false
	var close_btn := find_child("CloseButton", true, false) as Button
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	var skip_btn := find_child("SkipButton", true, false) as Button
	if skip_btn != null:
		skip_btn.pressed.connect(_on_skip_pressed)

# Loads the topic's steps and shows step 0. Pauses the tree by default,
# mirroring PauseMenu.open() — tutorial callouts freeze gameplay while
# shown. should_pause=false (issue #608) opts a topic out of that freeze
# for triggers that can fire mid-gameplay (e.g. an achievement unlocking
# mid-combat), where halting the tree would stall unrelated systems
# (dungeon entrance detection, etc.) instead of just pausing input.
func open(topic_id: String, should_pause: bool = true) -> void:
	visible = true
	_topic_id = topic_id
	_steps = TutorialCatalog.steps_for(topic_id)
	_step_index = 0
	_paused_on_open = should_pause
	if should_pause:
		get_tree().paused = true
	_show_step(_step_index)

# Advances to the next step. Running off the end of the step list finishes
# the topic (same effect as skip(), reached a different way).
func advance() -> void:
	_step_index += 1
	if _step_index >= _steps.size():
		_finish()
		return
	_show_step(_step_index)

# Immediately abandons the remaining steps in the topic, regardless of the
# current step index.
func skip() -> void:
	_finish()

# Internal: unpauses the tree (only if this open() call paused it) and
# hides the overlay. Does not emit `finished` on its own — callers that
# need the "topic ended" signal go through _finish() (advance-past-end /
# skip), not close() directly.
func close() -> void:
	if _paused_on_open:
		get_tree().paused = false
	_paused_on_open = false
	visible = false

func _finish() -> void:
	var topic_id := _topic_id
	close()
	finished.emit(topic_id)

func _show_step(index: int) -> void:
	if index < 0 or index >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[index]
	var label := find_child("StepLabel", true, false) as Label
	if label != null:
		label.text = String(step.get("text", ""))
	_position_for_target(String(step.get("target_group", "")))
	step_shown.emit(_topic_id, index)

# Resolves target_group to a Control via get_first_node_in_group and either
# positions the highlight box around it (with small padding) or, when the
# group is empty / resolves to nothing / isn't a Control, hides the
# highlight box and falls back to the centered text bubble.
func _position_for_target(target_group: String) -> void:
	var box := find_child("HighlightBox", true, false) as Control
	var bubble := find_child("Bubble", true, false) as Control
	var target: Node = null
	if target_group != "":
		target = get_tree().get_first_node_in_group(target_group)
	if target != null and target is Control:
		var rect: Rect2 = (target as Control).get_global_rect()
		if box != null:
			box.global_position = rect.position - Vector2(_HIGHLIGHT_PADDING, _HIGHLIGHT_PADDING)
			box.size = rect.size + Vector2(_HIGHLIGHT_PADDING, _HIGHLIGHT_PADDING) * 2
			box.visible = true
		if bubble != null:
			bubble.set_anchors_preset(Control.PRESET_TOP_LEFT)
			bubble.global_position = Vector2(rect.position.x, rect.position.y + rect.size.y + _HIGHLIGHT_PADDING * 2)
	else:
		if box != null:
			box.visible = false
		if bubble != null:
			bubble.set_anchors_preset(Control.PRESET_CENTER)

func _on_close_pressed() -> void:
	advance()

func _on_skip_pressed() -> void:
	skip()
