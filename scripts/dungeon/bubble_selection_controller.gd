class_name BubbleSelectionController
extends RefCounted

# Issue #196: pure navigation logic for an NPC speech-bubble menu.
#
# Owns the "currently highlighted option" cursor. Decoupled from the scene
# tree so it can be unit-tested without instantiating UI. The bubble UI
# funnels input through move_next / move_prev / confirm and renders whatever
# current_index() reports.
#
# Enabled mask can be either an Array[bool] (static) or a Callable taking an
# int index and returning bool (re-evaluated per step, so navigation reflects
# state changes — e.g. a "Get a beer" row disabling itself after the player
# spends their gold).

var _count: int = 0
var _mask  # Array[bool] or Callable(int) -> bool
var _cursor: int = -1


static func make(count: int, mask) -> BubbleSelectionController:
	var c := BubbleSelectionController.new()
	c._count = count
	c._mask = mask
	c._cursor = c._first_enabled()
	return c


func current_index() -> int:
	return _cursor


func confirm() -> int:
	if _cursor == -1:
		return -1
	if not _is_enabled(_cursor):
		return -1
	return _cursor


func move_next() -> void:
	_step(1)


func move_prev() -> void:
	_step(-1)


func _step(direction: int) -> void:
	if _cursor == -1:
		return
	var i := _cursor
	for _attempt in _count:
		i = (i + direction + _count) % _count
		if _is_enabled(i):
			_cursor = i
			return


func _is_enabled(i: int) -> bool:
	if _mask is Callable:
		return bool((_mask as Callable).call(i))
	if _mask is Array:
		return bool(_mask[i])
	return false


func _first_enabled() -> int:
	for i in _count:
		if _is_enabled(i):
			return i
	return -1
