class_name CharacterMutator
extends RefCounted

# Write gateway for CharacterData. Routes all stat mutations through one
# place; CharacterData remains readable directly everywhere it already is.
#
# Callers that previously passed CharacterData to DamageResolver or
# ReviveSystem now pass a CharacterMutator instead — the mutator calls
# those modules internally so callers don't need to know about them.

var data: CharacterData

func _init(character: CharacterData) -> void:
	data = character

func apply_damage(attacker_stats, rng: RandomNumberGenerator = null) -> int:
	if data == null or attacker_stats == null:
		return 0
	return DamageResolver.apply(attacker_stats, data, rng)

func revive() -> int:
	if data == null:
		return 0
	return ReviveSystem.revive(data)

func apply_stat_delta(stat_name: String, delta: float) -> void:
	if data == null:
		return
	data.apply_stat_delta(stat_name, delta)
