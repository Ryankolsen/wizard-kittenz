class_name RoomCodeGenerator
extends RefCounted

# Generates the 5-character room codes friends type into the lobby.
# Pure data — Nakama integration is a separate layer that takes a
# generated code and registers it with the matchmaker. Local-only
# generation lets the lobby UI surface a code immediately while the
# network round-trip is in flight.
#
# Charset excludes confusable glyphs (0/O, 1/I/L) so a friend reading
# the code aloud doesn't lose 30 seconds to typos. The acceptance
# criterion only requires "uppercase alphanumeric"; the trimmed set is
# a strict subset and stays within that contract.
const CODE_LENGTH: int = 5
const CHARSET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed: int = -1) -> void:
	# Same seed sentinel convention as NameSuggester / DungeonGenerator:
	# negative -> randomize(), any non-negative seed (including 0) is
	# deterministic. Tests pin a seed; production calls leave the default.
	if seed < 0:
		_rng.randomize()
	else:
		_rng.seed = seed

func generate() -> String:
	var out := ""
	for _i in range(CODE_LENGTH):
		out += CHARSET[_rng.randi_range(0, CHARSET.length() - 1)]
	return out
