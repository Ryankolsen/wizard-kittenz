class_name FloorMapState
extends RefCounted

# Pure-data reveal tracker for the minimap (PRD #304). One instance per
# floor; mark_revealed is idempotent so per-frame "you're in room N" ticks
# don't inflate the set. Renderer reads revealed_ids(); writer is
# RoomRevealBridge.
#
# Per-floor reset (clear on floor advance) lands in #308; this slice only
# needs the in-memory shape.

var _revealed: Dictionary = {}

func mark_revealed(room_id: int) -> void:
	_revealed[room_id] = true

func is_revealed(room_id: int) -> bool:
	return _revealed.get(room_id, false)

func revealed_ids() -> Array:
	var ids: Array = []
	for k in _revealed.keys():
		ids.append(int(k))
	return ids

# Convenience constructor for RoomRevealBridge.bind(): produces a fresh
# state with the start room pre-revealed so the chip shows the player's
# origin rectangle before any movement.
static func with_start_revealed(start_id: int) -> FloorMapState:
	var s := FloorMapState.new()
	s.mark_revealed(start_id)
	return s
