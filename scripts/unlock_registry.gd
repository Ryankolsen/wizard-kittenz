class_name UnlockRegistry
extends RefCounted

# Data-driven gate over the class/tier roster. Each condition is a Dictionary
# of the form {id, stat, threshold}: when tracker.get_stat(stat) >= threshold,
# the id is unlocked. Logic stays in this class; the *list* of conditions is
# data, so adding a new lockable class is a matter of appending an entry —
# not editing this file. Same shape as the SkillTree factory layer (graph
# topology in data, traversal helpers in code).
#
# Sentinel id "<base>" — a sentinel marker that means "always unlocked"; used
# for starter classes that shouldn't appear gated. Stored in the registry as
# a list of strings rather than full conditions.

const STARTER_CLASSES := ["mage", "thief"]

# Default conditions list for the shipping registry. New entries here unlock
# new content without touching this file's logic — that's the data-driven
# acceptance criterion. Listed by id, stat path (resolved by
# MetaProgressionTracker.get_stat), and threshold (>=).
const DEFAULT_CONDITIONS: Array = [
	{"id": "ninja", "stat": "dungeons_completed", "threshold": 5},
	{"id": "archmage", "stat": "max_level_per_class.mage", "threshold": 5},
]

var conditions: Array = []

static func make_default() -> UnlockRegistry:
	return from_conditions(DEFAULT_CONDITIONS)

# Lets tests (and any future "load from JSON file" path) supply their own
# condition list, including ones not present in DEFAULT_CONDITIONS — the
# data-driven extensibility test exercises this.
static func from_conditions(arr: Array) -> UnlockRegistry:
	var r := UnlockRegistry.new()
	for entry in arr:
		if entry is Dictionary:
			r.conditions.append(entry.duplicate())
	return r

# Returns true if `id` is unlocked. Starter classes are always unlocked. Any
# other id falls through to its condition; missing condition => locked.
func is_unlocked(id: String, tracker: MetaProgressionTracker) -> bool:
	var key := id.to_lower()
	if STARTER_CLASSES.has(key):
		return true
	if tracker == null:
		return false
	for cond in conditions:
		if String(cond.get("id", "")).to_lower() != key:
			continue
		var stat_path := String(cond.get("stat", ""))
		var threshold := int(cond.get("threshold", 0))
		return tracker.get_stat(stat_path) >= threshold
	return false

# Returns the list of currently-unlocked ids (per the conditions in this
# registry, evaluated against `tracker`). Starter classes are not included
# in this projection — the screen layer uses unlocked_ids() for "what's
# *gated* and now open"; starter classes are always available and don't
# need to appear in the list.
func check_all(tracker: MetaProgressionTracker) -> Array:
	var out: Array = []
	if tracker == null:
		return out
	for cond in conditions:
		var id := String(cond.get("id", ""))
		if is_unlocked(id, tracker):
			out.append(id)
	return out

# Computes the set of ids that have just transitioned from locked to
# unlocked. The screen layer / notification flow can call this after each
# tracker mutation to fire a "new class available!" toast.
func newly_unlocked(prev: Array, tracker: MetaProgressionTracker) -> Array:
	var current := check_all(tracker)
	var out: Array = []
	for id in current:
		if not prev.has(id):
			out.append(id)
	return out
