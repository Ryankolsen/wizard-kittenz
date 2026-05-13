class_name QuitDungeonHandler
extends RefCounted

# Quit Dungeon exit logic (PRD #42, #45). Pulled out of PauseMenu so the
# save-vs-skip branch is exercised by unit tests without a scene tree.
#
# Solo path  (session == null): writes a save via SaveManager so the
# player can resume next launch.
# Multiplayer (session != null): no save written — the run's XP and loot
# already live on GameState.current_character in memory; the multiplayer
# leave is treated as "step out of the party," not "persist this run to
# disk." The XP earned this run stays applied to the CharacterData
# instance, so a subsequent solo run starts from the leveled-up state.
#
# The branch is non-null vs null, not is_active(). A test or pre-
# handshake CoopSession that exists but hasn't started a run is still a
# multiplayer-shape caller; the right behavior is to skip the save.
#
# Returns true on a normal exit, false if the call was a no-op against
# a null character (defensive — the caller wouldn't otherwise know to
# skip the scene change).

static func save_and_exit(c: CharacterData, session: CoopSession, path: String = SaveManager.DEFAULT_PATH, tree: SkillTree = null) -> bool:
	if c == null:
		return false
	if session != null:
		return true
	SaveManager.save(c, path, tree)
	return true
