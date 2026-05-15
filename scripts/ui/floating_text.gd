class_name FloatingText
extends Node2D

# Short-lived floating world-space text used for combat feedback.
# PRD #85 / issue #91 — surfaces "Miss" when a physical attack returns 0
# (miss or evade). The label rises a few pixels and fades over DURATION
# seconds, then queue_frees itself. Parent to the target node so the
# text follows brief positional movement.

const DURATION: float = 0.7
const RISE_PIXELS: float = 20.0
const LABEL_OFFSET: Vector2 = Vector2(-12, -22)

var _label: Label
var _elapsed: float = 0.0

func _ready() -> void:
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		_label.position = LABEL_OFFSET
		add_child(_label)

func set_text(text: String, color: Color = Color(1, 1, 1, 1)) -> void:
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		_label.position = LABEL_OFFSET
		add_child(_label)
	_label.text = text
	_label.modulate = color

# Spawn helper: create a FloatingText, parent it to target_node, set text.
# Returns the new node so callers can tweak position or cancel it.
static func spawn(target_node: Node, text: String, color: Color = Color(1, 1, 1, 1)) -> FloatingText:
	if target_node == null:
		return null
	var ft := FloatingText.new()
	target_node.add_child(ft)
	ft.set_text(text, color)
	return ft

func _process(delta: float) -> void:
	_elapsed += delta
	position.y -= delta * (RISE_PIXELS / DURATION)
	if _label != null:
		var alpha := clampf(1.0 - (_elapsed / DURATION), 0.0, 1.0)
		_label.modulate.a = alpha
	if _elapsed >= DURATION:
		queue_free()
