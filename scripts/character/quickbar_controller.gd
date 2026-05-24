class_name QuickbarController
extends Node

# Slice 2 of PRD #210. Thin input adapter: polls cast_slot_1..cast_slot_4
# each frame and dispatches to Quickbar.fire_slot. Re-emits slot_fired only
# when the cast actually succeeds (Spell.cast returned true), so a strict
# no-op cooldown / empty-slot / MP-gated press produces no signal and no
# HUD churn downstream (slice 3 wires HUD onto this signal).

const _QuickbarScript = preload("res://scripts/character/quickbar.gd")

signal slot_fired(slot: int)

var quickbar = null
var caster = null

# Polling is driven explicitly by Player._physics_process via _poll_inputs()
# rather than this node's own _process callback. That keeps the read on
# the same frame tick as the rest of Player's input pipeline (attack), and
# lets unit tests drive try_fire_slot() / _poll_inputs() deterministically.
func _poll_inputs() -> void:
	if quickbar == null:
		return
	for i in range(1, _QuickbarScript.SLOT_COUNT + 1):
		if Input.is_action_just_pressed("cast_slot_%d" % i):
			try_fire_slot(i)

# Public dispatch entry point. Routes a slot number into Quickbar.fire_slot
# and re-emits slot_fired only when the cast actually lands. Pulled out of
# _poll_inputs so tests can exercise the routing logic without leaning on
# Input.action_press, which has frame-scoped just_pressed semantics that
# don't reset within a single synchronous test body.
func try_fire_slot(n: int) -> bool:
	if quickbar == null:
		return false
	if not quickbar.fire_slot(n, caster):
		return false
	slot_fired.emit(n)
	return true
