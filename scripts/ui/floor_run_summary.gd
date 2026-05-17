class_name FloorRunSummary
extends RefCounted

# PRD #132 / issue #134 — lightweight data holder for the four stats
# shown on the congratulations screen after a dungeon floor clear.
# Assembled by main_scene at completion time from already-tracked
# state (enemies-slain counter + start-of-floor snapshots of XP and
# gold) and handed to the screen for display. No persistence, no
# scene tree.

var floor_number: int = 0
var enemies_slain: int = 0
var xp_earned: int = 0
var gold_earned: int = 0

func _init(
		p_floor_number: int = 0,
		p_enemies_slain: int = 0,
		p_xp_earned: int = 0,
		p_gold_earned: int = 0) -> void:
	floor_number = p_floor_number
	enemies_slain = p_enemies_slain
	xp_earned = p_xp_earned
	gold_earned = p_gold_earned
