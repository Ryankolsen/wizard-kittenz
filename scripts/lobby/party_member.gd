class_name PartyMember
extends RefCounted

# A party member holds two stat snapshots:
#   real_stats — the persistent character (what's saved, what XP applies to)
#   effective_stats — the in-game view, scaled down in co-op when this
#     player is over the party's floor level.
# In solo play the two are equal. PartyScaler.remove_scaling sets them
# back to equal on session end.
var real_stats: CharacterData
var effective_stats: CharacterData

static func from_character(c: CharacterData) -> PartyMember:
	var pm := PartyMember.new()
	pm.real_stats = c
	pm.effective_stats = PartyScaler.clone_stats(c)
	return pm

# Mutates effective_stats to the scaled view. Real stats are untouched —
# co-op session start should call this for every member after compute_floor.
func apply_scaling(floor_level: int) -> void:
	effective_stats = PartyScaler.scale_stats(real_stats, floor_level)
