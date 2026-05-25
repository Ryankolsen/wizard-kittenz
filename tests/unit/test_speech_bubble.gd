extends GutTest

# Touch regression (#197 follow-up): the speech bubble navigated + confirmed
# via _unhandled_input, so move_up/move_down/attack only worked from a desktop
# keyboard. The on-screen joystick + attack button drive those actions through
# Input.action_press(), which never emits an InputEvent — so on a deployed
# phone the menu opened (once the NPC was fixed) but could be neither navigated
# nor confirmed. These tests pin the polling path (Input.is_action_just_pressed
# read in _physics_process) that works on both keyboard and touch.

const BUBBLE_SCENE_PATH := "res://scenes/speech_bubble.tscn"


# is_action_just_pressed() compares an action's press-frame to the current
# frame and releasing does NOT clear it, so a press in one test stays "just
# pressed" for any later test that runs in the same synchronous frame. Advance
# a frame between tests so each test's press is the only one current.
func before_each() -> void:
	await get_tree().process_frame


class _ConfirmRecorder extends Node:
	var last_effect_id: String = ""
	var calls: int = 0

	func on_confirmed(effect_id: String) -> void:
		last_effect_id = effect_id
		calls += 1


func _make_list() -> NPCOptionList:
	return NPCOptionList.make([
		NPCOption.make("First", "do_first"),
		NPCOption.make("Second", "do_second"),
	] as Array[NPCOption])


func _make_open_bubble() -> SpeechBubble:
	var bubble: SpeechBubble = load(BUBBLE_SCENE_PATH).instantiate()
	add_child_autofree(bubble)
	var list := _make_list()
	var mask := func(i: int) -> bool: return list.get_at(i).is_enabled()
	var controller := BubbleSelectionController.make(list.size(), mask)
	bubble.open(list, controller)
	return bubble


func test_move_down_polling_advances_cursor():
	var bubble := _make_open_bubble()
	assert_eq(bubble.selection.current_index(), 0, "precondition: cursor starts on row 0")
	Input.action_press("move_down")
	bubble._physics_process(0.0)
	Input.action_release("move_down")
	assert_eq(bubble.selection.current_index(), 1,
		"polling move_down advances the cursor (touch joystick path)")


func test_move_up_polling_retreats_cursor():
	var bubble := _make_open_bubble()
	bubble.move_next()  # cursor -> row 1
	Input.action_press("move_up")
	bubble._physics_process(0.0)
	Input.action_release("move_up")
	assert_eq(bubble.selection.current_index(), 0,
		"polling move_up retreats the cursor (touch joystick path)")


func test_attack_polling_confirms_highlighted_option():
	var bubble := _make_open_bubble()
	var rec := _ConfirmRecorder.new()
	add_child_autofree(rec)
	bubble.option_confirmed.connect(rec.on_confirmed)
	Input.action_press("attack")
	bubble._physics_process(0.0)
	Input.action_release("attack")
	assert_eq(rec.calls, 1, "polling attack confirms exactly once (touch attack-button path)")
	assert_eq(rec.last_effect_id, "do_first",
		"confirm emits the highlighted row's effect_id")
