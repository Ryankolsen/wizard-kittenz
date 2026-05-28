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
const TYPE_WET := "wet"
const TYPE_SLOWNESS := "slowness"
const TYPE_CONFUSION := "confusion"

# Single declarative source of truth for every kind: default duration +
# is_pickup. make() dispatches construction by id and reads the default
# duration from here, so "declared but not in the factory" gaps (the old
# wet/slowness/confusion case) cannot recur.
const _REGISTRY := {
	TYPE_CATNIP: {"default_duration": 8.0, "is_pickup": true},
	TYPE_ALE: {"default_duration": 10.0, "is_pickup": true},
	TYPE_MUSHROOMS: {"default_duration": 6.0, "is_pickup": true},
	TYPE_WET: {"default_duration": 4.0, "is_pickup": false},
	TYPE_SLOWNESS: {"default_duration": 3.0, "is_pickup": false},
	TYPE_CONFUSION: {"default_duration": 3.0, "is_pickup": false},
}

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

# Total factory over every registered kind. `duration < 0` resolves to the
# registry default for that kind; an explicit duration is passed through
# (debuffs / caller-tuned buffs). Unknown id returns null so callers can
# no-op on a stale save / typo without crashing — the dungeon spawner
# relies on this late-gate.
static func make(type_id: String, duration: float = -1.0) -> PowerUpEffect:
	if not _REGISTRY.has(type_id):
		return null
	var dur: float = duration if duration >= 0.0 else float(_REGISTRY[type_id]["default_duration"])
	match type_id:
		TYPE_CATNIP:
			var catnip := CatnipEffect.new()
			catnip.duration = dur
			catnip.remaining = dur
			return catnip
		TYPE_ALE:
			var ale := AleEffect.new()
			ale.duration = dur
			ale.remaining = dur
			return ale
		TYPE_MUSHROOMS:
			var mushrooms := MushroomEffect.new()
			mushrooms.duration = dur
			mushrooms.remaining = dur
			return mushrooms
		TYPE_WET:
			return WetEffect.new(dur)
		TYPE_SLOWNESS:
			return SlownessEffect.new(dur)
		TYPE_CONFUSION:
			return ConfusionEffect.new(dur)
	return null

static func is_pickup(type_id: String) -> bool:
	if not _REGISTRY.has(type_id):
		return false
	return bool(_REGISTRY[type_id]["is_pickup"])

static func default_duration(type_id: String) -> float:
	if not _REGISTRY.has(type_id):
		return -1.0
	return float(_REGISTRY[type_id]["default_duration"])
