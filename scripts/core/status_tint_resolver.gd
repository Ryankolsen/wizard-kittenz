class_name StatusTintResolver
extends RefCounted

# Pure resolver mapping the set of active player-effect ids to a single tint
# colour (PRD #518 / issue #536). Replaces the old wet-specific
# Player._apply_wet_tint routine, which hardcoded a single branch and forced
# every other state back to white — a second branch (petrify) would have
# fought it over `modulate`. Priority order is documented here once, so
# adding the next status effect is a row in `_PRIORITY`, not another branch.
#
# Takes an Array (or any container answering `.has(id)`) of currently-active
# type ids — Player passes PowerUpManager.active_ids(). No SceneTree deps, so
# every priority edge is unit testable without a Sprite2D.

const PETRIFY_TINT := Color(0.55, 0.55, 0.58, 1.0)   # desaturated stone-grey
# Matches the pre-existing Player._WET_TINT exactly so extraction doesn't
# change wet's look.
const WET_TINT := Color(0.55, 0.75, 1.0, 1.0)
# Slowness previously had no tint at all (Player.gd's SlownessEffect doc:
# "applies no visual tint"). Giving it one here is what makes the priority
# order meaningful for all three effects rather than just petrify-vs-wet.
const SLOWNESS_TINT := Color(0.75, 0.7, 0.4, 1.0)    # dull, sluggish amber
const DEFAULT_TINT := Color.WHITE

# Highest priority first: petrify > wet > slowness (PRD #518 / issue #536
# acceptance criteria). The first id in this list that's present in the
# active set wins.
const _PRIORITY := [
	PowerUpEffect.TYPE_PETRIFY,
	PowerUpEffect.TYPE_WET,
	PowerUpEffect.TYPE_SLOWNESS,
]

static func resolve(active_effect_ids) -> Color:
	if active_effect_ids == null:
		return DEFAULT_TINT
	for type_id in _PRIORITY:
		if active_effect_ids.has(type_id):
			return _tint_for(type_id)
	return DEFAULT_TINT

static func _tint_for(type_id: String) -> Color:
	match type_id:
		PowerUpEffect.TYPE_PETRIFY:
			return PETRIFY_TINT
		PowerUpEffect.TYPE_WET:
			return WET_TINT
		PowerUpEffect.TYPE_SLOWNESS:
			return SLOWNESS_TINT
	return DEFAULT_TINT
