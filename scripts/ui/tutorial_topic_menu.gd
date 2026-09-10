class_name TutorialTopicMenu
extends PanelContainer

# Help-icon topic picker popup (#610, PRD #596). Lists every tutorial topic
# from TutorialCatalog.topic_ids() by a short human-readable label and
# emits the chosen topic id on click. Purely a "pick one of N" UI -- it
# never calls TutorialSequencer, TutorialProgress, or GameState itself; the
# caller (a later wiring slice) listens for topic_selected and acts on it.
#
# is_touch is passed into populate() explicitly, mirroring
# TutorialTrigger.should_trigger's is_touch parameter, so callers pass
# TouchControls.is_touch_platform() and tests can drive both platform
# branches without depending on the real OS.has_feature() result. On
# desktop, movement_attack is excluded entirely -- it has no desktop
# content, so showing it would open an overlay whose steps never render.

signal topic_selected(topic_id: String)
signal closed()

const TOPIC_LABELS := {
	"main_menu": "Main Menu",
	"movement_attack": "Movement & Attack",
	"pause_menu": "Pause Menu",
	"equip_gear": "Equipping Gear",
	"assign_skills": "Assigning Skills",
	"tavern": "The Tavern",
	"achievements": "Achievements",
}

const _DESKTOP_EXCLUDED_TOPICS := ["movement_attack"]

func _ready() -> void:
	var close_btn := find_child("CloseButton", true, false) as Button
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	populate(TouchControls.is_touch_platform())

# Rebuilds the topic list for the given platform. Safe to call more than
# once (e.g. from tests overriding the real platform read) -- clears any
# previously built rows first.
func populate(is_touch: bool) -> void:
	var list := _topic_list()
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.free()
	for topic_id in TutorialCatalog.topic_ids():
		if not is_touch and _DESKTOP_EXCLUDED_TOPICS.has(topic_id):
			continue
		list.add_child(_make_topic_row(topic_id))

func _make_topic_row(topic_id: String) -> Button:
	var btn := Button.new()
	btn.name = "TopicRow_%s" % topic_id
	btn.text = TOPIC_LABELS.get(topic_id, topic_id)
	btn.pressed.connect(_on_topic_row_pressed.bind(topic_id))
	return btn

func _topic_list() -> VBoxContainer:
	return find_child("TopicList", true, false) as VBoxContainer

func _on_topic_row_pressed(topic_id: String) -> void:
	topic_selected.emit(topic_id)

func _on_close_pressed() -> void:
	closed.emit()

# Test/inspection helper: every currently-built topic row, in list order.
func get_topic_rows() -> Array[Button]:
	var list := _topic_list()
	var rows: Array[Button] = []
	if list == null:
		return rows
	for child in list.get_children():
		if child is Button:
			rows.append(child)
	return rows

# Test/inspection helper: the row Button for a given topic id, or null if
# it isn't currently rendered (e.g. movement_attack on desktop).
func get_topic_row(topic_id: String) -> Button:
	var list := _topic_list()
	if list == null:
		return null
	return list.get_node_or_null("TopicRow_%s" % topic_id) as Button
