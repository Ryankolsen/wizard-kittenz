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
# The current step's unwrapped text, re-wrapped in _position_for_target once
# the bubble's actual width for this frame is known (see _wrap_text).
var _current_step_text: String = ""

const _HIGHLIGHT_PADDING := 6.0
# Node2D targets (e.g. Bartender, issue #609) have no natural bounding rect
# the way a Control does, so the highlight box is a fixed-size square
# centered on the target's projected screen position.
const _NODE2D_HIGHLIGHT_SIZE := Vector2(64.0, 64.0)

# The project's design canvas is only 480x270 (project.godot stretch/mode
# "canvas_items"). A near-square bubble (previously 240x60-and-growing)
# still ate a large chunk of that height. A wide, short banner docked at
# the top uses the same text budget in far less vertical space, so it
# never covers more than a thin strip of the screen regardless of target
# position. Width is computed per-call as most of the viewport (see
# _position_for_target); this is only the height floor/minimum.
const _BUBBLE_MIN_HEIGHT := 40.0
const _BUBBLE_MARGIN := 10.0
const _BUBBLE_CONTENT_MARGIN := 12.0

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
	_current_step_text = String(step.get("text", ""))
	_position_for_target(String(step.get("target_group", "")))
	step_shown.emit(_topic_id, index)

# Resolves target_group to a node via get_first_node_in_group and either
# positions the highlight box around it (with small padding) or, when the
# group is empty / resolves to nothing / resolves to an unsupported node
# type, hides the highlight box and falls back to the centered text bubble.
#
# Two target shapes are supported:
# - Control: uses its own global_rect as the highlight rect directly.
# - Node2D (issue #609 — e.g. Bartender, a world-space sprite with no
#   Control bounding rect of its own): projects global_position through the
#   viewport's active canvas transform (which already folds in the current
#   Camera2D's offset/zoom) to a screen-space point, then draws a fixed-size
#   box centered on that point.
func _position_for_target(target_group: String) -> void:
	var box := find_child("HighlightBox", true, false) as Control
	var bubble := find_child("Bubble", true, false) as Control
	var target: Node = null
	if target_group != "":
		target = get_tree().get_first_node_in_group(target_group)
	var rect: Rect2
	var has_rect := false
	if target != null and target is Control:
		rect = (target as Control).get_global_rect()
		has_rect = true
	elif target != null and target is Node2D:
		var screen_pos: Vector2 = get_viewport().get_canvas_transform() * (target as Node2D).global_position
		rect = Rect2(screen_pos - _NODE2D_HIGHLIGHT_SIZE / 2.0, _NODE2D_HIGHLIGHT_SIZE)
		has_rect = true
	if box != null:
		box.visible = has_rect
		if has_rect:
			box.global_position = rect.position - Vector2(_HIGHLIGHT_PADDING, _HIGHLIGHT_PADDING)
			box.size = rect.size + Vector2(_HIGHLIGHT_PADDING, _HIGHLIGHT_PADDING) * 2

	if bubble == null:
		return
	bubble.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# A wide banner rather than a near-square card -- most of the viewport
	# width, kept short by wrapping to few lines instead of many.
	var bubble_width: float = maxf(0.0, viewport_size.x - _BUBBLE_MARGIN * 2.0)
	var content_width: float = maxf(0.0, bubble_width - _BUBBLE_CONTENT_MARGIN * 2.0)
	var max_bubble_height: float = maxf(_BUBBLE_MIN_HEIGHT, viewport_size.y - _BUBBLE_MARGIN * 2.0)

	var bubble_height := _BUBBLE_MIN_HEIGHT
	var label := find_child("StepLabel", true, false) as Label
	if label != null:
		# Label's own *autowrap* minimum-size computation is unreliable
		# before the control has gone through a real layout pass (it can
		# report a wildly inflated height, dragging the whole bubble along
		# via Godot's automatic clamp-to-minimum-size). Word-wrap the text
		# ourselves with direct font metrics instead and turn autowrap off,
		# which makes the label's (and therefore the bubble's) own reported
		# minimum size a simple, reliable per-line calculation again.
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		label.text = _wrap_text(_current_step_text, font, font_size, content_width)
		bubble_height = clampf(bubble.get_combined_minimum_size().y, _BUBBLE_MIN_HEIGHT, max_bubble_height)

	var bubble_size := Vector2(bubble_width, bubble_height)
	bubble.size = bubble_size
	# Always dock at the top of the screen as a banner, clear of the
	# highlight box below it -- a fixed, predictable location that only
	# ever covers a thin strip at the top rather than following the
	# target and potentially landing over the player mid-gameplay.
	bubble.global_position = Vector2(_BUBBLE_MARGIN, _BUBBLE_MARGIN)

# Greedy word-wrap using the label's actual font metrics, breaking at
# max_width. Bypasses Label's built-in autowrap so its minimum-size stays a
# simple, reliable per-line calculation (see _position_for_target). A single
# word wider than max_width is kept on its own line rather than split.
func _wrap_text(text: String, font: Font, font_size: int, max_width: float) -> String:
	if text == "" or font == null:
		return text
	var words := text.split(" ")
	var lines: Array[String] = []
	var current := ""
	for word in words:
		var candidate := word if current == "" else current + " " + word
		if current != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			lines.append(current)
			current = word
		else:
			current = candidate
	if current != "":
		lines.append(current)
	return "\n".join(lines)

func _on_close_pressed() -> void:
	advance()

func _on_skip_pressed() -> void:
	skip()
