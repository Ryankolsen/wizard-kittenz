class_name InteractableNPC
extends Node2D

# Issue #197: reusable NPC base. Encapsulates the proximity Area2D gate, the
# attack-key trigger that opens the bubble menu, the mounting/teardown of
# SpeechBubble, and dispatch of the confirmed option's effect_id back to a
# virtual _handle_effect(effect_id) hook that subclasses override.
#
# Subclasses (Bartender today; future shopkeeper / quest-giver NPCs) provide:
#   - a ProximityArea (Area2D child) in their scene file — wiring of
#     body_entered / body_exited happens here in _ready
#   - _build_option_list()  → NPCOptionList   (their menu rows)
#   - _handle_effect(id)    → void            (their per-option behavior)
#
# Lifecycle:
#   player enters range  → _player_in_range = true
#   attack pressed       → _open_bubble() if no bubble already open
#   option confirmed     → _handle_effect(effect_id); subclass decides whether
#                          to close the bubble (e.g. Exit → close; Shop →
#                          close + emit shop_requested so the room can mount
#                          the overlay)
#   player exits range   → bubble auto-closes
#
# The base also gates _unhandled_input: while a bubble is mounted, the NPC
# itself ignores attack presses (the bubble's own _unhandled_input handles
# Confirm). Without the gate, pressing attack to confirm would also try to
# open a second bubble on the same frame.

const SPEECH_BUBBLE_SCENE_PATH := "res://scenes/speech_bubble.tscn"

var _player_in_range: bool = false
var _bubble: SpeechBubble = null


func _ready() -> void:
	var area := get_node_or_null("ProximityArea") as Area2D
	if area != null:
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
		if not area.body_exited.is_connected(_on_body_exited):
			area.body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if _bubble != null:
		return
	if event.is_action_pressed("attack"):
		_on_attack_pressed()
		get_viewport().set_input_as_handled()


# Returns the currently-mounted bubble or null. Test seam — lets tests inspect
# the bubble's selection controller / option list directly without poking at
# private state. Subclasses also use this when reacting to "shop closed,
# reopen menu"-style flows (see Bartender + BarRoom's _on_shop_closed).
func get_bubble() -> SpeechBubble:
	return _bubble


# Opens the bubble menu. Public so callers (e.g. BarRoom on shop close) can
# request a fresh menu without going through input. No-op if the bubble is
# already mounted or the player isn't in range.
func open_menu() -> void:
	if _bubble != null or not _player_in_range:
		return
	_open_bubble()


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("players"):
		return
	_on_player_entered_range()


func _on_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("players"):
		return
	_on_player_exited_range()


func _on_player_entered_range() -> void:
	_player_in_range = true


func _on_player_exited_range() -> void:
	_player_in_range = false
	_close_bubble()


func _on_attack_pressed() -> void:
	if not _player_in_range:
		return
	if _bubble != null:
		return
	_open_bubble()


func _open_bubble() -> void:
	var list := _build_option_list()
	if list == null or list.size() == 0:
		return
	# Use a Callable mask so disabled-state stays live across navigation steps
	# — matches the BubbleSelectionController contract (see #196).
	var mask := func(i: int) -> bool: return list.get(i).is_enabled()
	var controller := BubbleSelectionController.make(list.size(), mask)
	var bubble: SpeechBubble = load(SPEECH_BUBBLE_SCENE_PATH).instantiate()
	add_child(bubble)
	bubble.open(list, controller)
	bubble.option_confirmed.connect(_on_option_confirmed)
	bubble.dismissed.connect(_on_bubble_dismissed)
	_bubble = bubble


func _close_bubble() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		# dismiss() emits dismissed → _on_bubble_dismissed nulls _bubble.
		_bubble.dismiss()
	else:
		_bubble = null


func _on_option_confirmed(effect_id: String) -> void:
	_handle_effect(effect_id)


func _on_bubble_dismissed() -> void:
	_bubble = null


# --- Virtual hooks for subclasses -----------------------------------------

# Override to declare the NPC's menu rows. Default is an empty list (no menu
# opens). Re-built on every _open_bubble() so per-row predicates re-evaluate
# off current state.
func _build_option_list() -> NPCOptionList:
	return NPCOptionList.make([] as Array[NPCOption])


# Override to react to the confirmed option's effect_id. The base does not
# auto-dismiss the bubble — the subclass decides whether confirmation closes
# the menu (e.g. "close" → _close_bubble) or keeps it open (e.g. a future
# "buy a beer" that stays on the menu so the player can also visit the shop).
func _handle_effect(_effect_id: String) -> void:
	pass
