class_name BubbleRowHitTest
extends RefCounted

# Issue #630: pure geometric hit-testing for a speech-bubble menu's rows.
#
# Given an Array[Rect2] of row rectangles (one per menu row, in order) and a
# Vector2 point, resolves the index of the containing row, or -1 if the
# point falls inside none of them. No dependency on Control, Node,
# _gui_input, or any Godot input event type — plain geometry in, plain int
# out. Stateless, so a single static func is all that's needed (unlike
# BubbleSelectionController, which owns cursor state across calls).


static func row_at(rects: Array[Rect2], point: Vector2) -> int:
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1
