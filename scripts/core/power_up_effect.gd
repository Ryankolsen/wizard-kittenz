class_name PowerUpEffect
extends RefCounted

# Base class for time-bounded power-up effects. Each subclass implements
# `_on_apply` / `_on_remove` to mutate the target's stats and (optionally)
# overrides `tick` for per-frame behavior (e.g. Mushroom's interval signal).
#
# Targets are duck-typed — a CharacterData satisfies the `speed: float` and
# `attack: int` shape that Catnip / Ale need. Same pattern as DamageResolver.
#
# The applied delta — not the pre-buff value — is what gets reverted on
# remove, so any concurrent external mutation (e.g. a level-up that bumps
# speed) is preserved when the buff drops off.

const TYPE_CATNIP := "catnip"
const TYPE_ALE := "ale"
const TYPE_MUSHROOMS := "mushrooms"

var type: String = ""
var duration: float = 0.0
var remaining: float = 0.0
var _target = null

func refresh() -> void:
	remaining = duration

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	remaining = maxf(0.0, remaining - dt)

func is_expired() -> bool:
	return remaining <= 0.0

func apply_to(target) -> void:
	_target = target
	_on_apply(target)

func remove() -> void:
	if _target != null:
		_on_remove(_target)
	_target = null

func _on_apply(_t) -> void:
	pass

func _on_remove(_t) -> void:
	pass

# Factory for the three power-up kinds. Unknown id returns null so callers
# can no-op on a stale save / typo without crashing — same shape as
# CharacterFactory.create_default fallback.
static func make(type_id: String) -> PowerUpEffect:
	match type_id:
		TYPE_CATNIP:
			return CatnipEffect.new()
		TYPE_ALE:
			return AleEffect.new()
		TYPE_MUSHROOMS:
			return MushroomEffect.new()
	return null
