class_name Bartender
extends Node2D

# In-dungeon bartender NPC (issue #183). Sits behind the bar counter in the
# bar room. An Area2D child detects when the player walks into proximity;
# while in range, pressing the attack action emits shop_requested so the
# bar room (or any caller) can open ShopScreen with the live run ledger.
#
# Decisions:
# - The proximity Area2D filters body_entered on the "players" group tag
#   (Player.gd adds it at startup), matching the same contract ExitZone uses
#   in the bar room. Enemies don't get into the bar (EnemyBarrier pushback),
#   but the filter is defensive in case the barrier is bypassed.
# - Attack input is observed directly via Input.is_action_just_pressed in
#   _unhandled_input so the bartender can mark the event handled and stop
#   the player's own attack from firing on the same frame (AC: "Player
#   attack animation/damage suppressed while shop interaction is active" —
#   here applied at the trigger point so the attack press that opens the
#   shop doesn't also swing the weapon). When out of range we leave the
#   event alone so attacks elsewhere in the dungeon work as normal.
# - _on_attack_pressed is the test seam (matches the API the issue's
#   red-green sketches call directly). It only emits when _player_in_range
#   is true; the input handler delegates to it so the gating logic lives in
#   one place.

signal shop_requested()

var _player_in_range: bool = false


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
	if event.is_action_pressed("attack"):
		_on_attack_pressed()
		get_viewport().set_input_as_handled()


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


func _on_attack_pressed() -> void:
	if not _player_in_range:
		return
	shop_requested.emit()
