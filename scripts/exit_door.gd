class_name ExitDoor
extends StaticBody2D

# Boss-room exit door (issue #98). Starts locked: a StaticBody2D collision
# blocks the player from walking through, and a closed-door visual is shown.
# When the dungeon's boss is killed, DungeonRunController emits
# boss_room_cleared; main_scene routes that edge into open(), which disables
# the blocking collision and swaps the visual to the open-door tint. A child
# Area2D trigger watches for the player's body entering while unlocked and
# emits player_exited_dungeon — main_scene treats that as "advance to the
# next dungeon" and drives the same finalize + reload chain the boss-clear
# path used to.
#
# The door is intentionally a StaticBody (blocks via the root's
# CollisionShape2D, not via the Area2D) so the locked-state physics are
# the same shape Godot already enforces against the player's CharacterBody2D.
# The Trigger Area2D exists only to detect the unlocked walk-through; it
# is always present, but _on_trigger_body_entered gates on is_locked so a
# pre-boss-kill brush against the door (impossible while collision is
# active, but defensible) doesn't emit the exit signal.

signal player_exited_dungeon()

var is_locked: bool = true


func _ready() -> void:
	var trigger := get_node_or_null("Trigger") as Area2D
	if trigger != null and not trigger.body_entered.is_connected(_on_trigger_body_entered):
		trigger.body_entered.connect(_on_trigger_body_entered)
	_refresh_visual()


# Transitions the door to its open state: blocking collision is disabled
# so the player can walk through, and the visual swaps to the unlocked
# variant. Idempotent — a second open() is a safe no-op so the wire layer
# doesn't have to dedupe boss_room_cleared re-fires.
func open() -> void:
	if not is_locked:
		return
	is_locked = false
	var coll := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if coll != null:
		coll.disabled = true
	_refresh_visual()


# Trigger callback for the child Area2D. Bodies entering while locked are
# ignored (the StaticBody collision should already block them, but the
# guard makes the contract explicit for the test that drives this directly
# with a fake body). Once unlocked, any body entering fires the exit signal
# — collision_mask on the trigger filters to the player layer so co-op
# remote kittens / loose physics bodies don't accidentally trip it.
func _on_trigger_body_entered(_body: Node) -> void:
	if is_locked:
		return
	player_exited_dungeon.emit()


func _refresh_visual() -> void:
	var locked_visual := get_node_or_null("LockedVisual")
	var open_visual := get_node_or_null("OpenVisual")
	if locked_visual != null:
		locked_visual.visible = is_locked
	if open_visual != null:
		open_visual.visible = not is_locked
