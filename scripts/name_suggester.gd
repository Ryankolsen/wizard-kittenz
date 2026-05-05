class_name NameSuggester
extends RefCounted

# Pool of silly default names used by Quick Start and the "Random Name"
# button on the Customize screen. Surfaces at least 12 entries so the
# acceptance criterion of "10+ silly names" is satisfied with headroom
# for further additions; the issue specifically calls out Bourbon Cat
# and Catnip McGee as exemplars.
const SILLY_NAMES: Array[String] = [
	"Bourbon Cat",
	"Catnip McGee",
	"Sir Whiskerbottom",
	"Princess Mittens",
	"Captain Floof",
	"Dr. Pawsworth",
	"Lord Snugglesworth",
	"Mr. Mustache",
	"Lady Pounce",
	"Baron von Purr",
	"Whiskey Whiskers",
	"Hairball Henry",
	"Senor Scratchington",
	"Mango Tango",
]

# Stateful: holds the previous draw so consecutive calls never repeat.
# RefCounted (not @autoload) — call sites instantiate one per session.
var _last: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed: int = -1) -> void:
	# Negative seed -> randomize() (fresh draw per construction). Any
	# non-negative seed (including 0) is deterministic. Same sentinel
	# convention as DungeonGenerator.generate.
	if seed < 0:
		_rng.randomize()
	else:
		_rng.seed = seed

# Returns a random name from the pool, guaranteed not equal to the most
# recent return value. Two-name pool degenerate case still alternates.
# An empty/single-entry pool would theoretically loop forever; the
# constant pool above ensures that's not reachable, and the SILLY_NAMES
# array is the single point of truth for content edits.
func get_random_name() -> String:
	if SILLY_NAMES.size() == 0:
		return ""
	if SILLY_NAMES.size() == 1:
		_last = SILLY_NAMES[0]
		return _last
	var pick: String
	while true:
		pick = SILLY_NAMES[_rng.randi_range(0, SILLY_NAMES.size() - 1)]
		if pick != _last:
			break
	_last = pick
	return pick
