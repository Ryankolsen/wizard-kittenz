class_name CongratulationsMessageBuilder
extends RefCounted

# PRD #132 / issue #133 — pure static helper that builds the
# headline string shown on the congratulations screen after a
# dungeon floor clear.
#
# Two branches:
#   - First-boss: returns a fixed celebratory message. The caller
#     decides whether this is the player's first-ever boss kill
#     (main_scene checks MetaProgressionTracker.dungeons_completed).
#   - Repeat: picks a random adjective from a curated pool and
#     interpolates it into a template. Caller owns the RNG so the
#     selection is deterministic under test.
#
# Stateless by design: no exported vars, no scene tree, no class
# state. Tests construct an RNG, seed it, and call build() directly.

const FIRST_BOSS_MESSAGE := "Congratulations on your first boss kill!"

const ADJECTIVE_POOL: Array[String] = [
	"pummeling",
	"destroying",
	"clobbering",
	"obliterating",
	"annihilating",
	"flattening",
	"vanquishing",
	"decimating",
	"eviscerating",
	"pulverizing",
]

static func build(is_first_boss: bool, rng: RandomNumberGenerator, boss_display_name: String = "") -> String:
	if is_first_boss:
		return FIRST_BOSS_MESSAGE
	var idx := rng.randi_range(0, ADJECTIVE_POOL.size() - 1)
	# Empty name falls back to the legacy "the boss" phrasing so callers that
	# haven't been updated (and legacy saves without a roster lookup) still
	# render a grammatical sentence.
	var target := boss_display_name if boss_display_name != "" else "the boss"
	return "Congratulations on %s %s!" % [ADJECTIVE_POOL[idx], target]
