class_name AchievementEffects
extends RefCounted

# PRD #512 / issue #515. Maps specific achievement unlocks to permanent
# gameplay effects (starting with "grant wall phase-through" for
# wall_walker, #514). Kept separate from AchievementService so that class
# stays reward-shape generic (gold/potion/item/tome/none via claim()) and
# never gains gameplay-specific knowledge like flipping a player's
# collision flag.
#
# Applied in the two situations the PRD requires for the effect to feel
# truly permanent:
# 1. Reactively — service.achievement_unlocked fires mid-session (e.g. the
#    5th dungeon clear), the currently active player is updated immediately,
#    with no claim step.
# 2. At construction (player/session start) — every id already present in
#    service.account.achievement_state is re-applied, since
#    achievement_unlocked won't re-fire for an already-unlocked id.
#
# Adding a second mapping later is a one-line addition to _EFFECTS, not a
# case-by-case rewrite of the wiring below.
const _EFFECTS := {
	"wall_walker": "_apply_wall_walker",
}

var _player: Player

func _init(service: AchievementService, player: Player) -> void:
	_player = player
	if service == null:
		return
	if not service.achievement_unlocked.is_connected(_on_achievement_unlocked):
		service.achievement_unlocked.connect(_on_achievement_unlocked)
	if service.account != null:
		for id in service.account.achievement_state.keys():
			_apply(id)

func _on_achievement_unlocked(id: String) -> void:
	_apply(id)

func _apply(id: String) -> void:
	if _player == null or not _EFFECTS.has(id):
		return
	call(_EFFECTS[id])

func _apply_wall_walker() -> void:
	_player.set_can_phase_through_walls(true)
