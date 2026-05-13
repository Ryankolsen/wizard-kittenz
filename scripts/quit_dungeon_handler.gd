class_name QuitDungeonHandler
extends RefCounted

# class_name resolution for sibling scripts is unreliable at script-parse
# time (see notes in pause_menu / audio_settings_manager commits). Preload
# the serializer to keep the QuitDungeon save path independent of load
# order.
const DungeonRunSerializerRef = preload("res://scripts/dungeon_run_serializer.gd")

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

static func save_and_exit(c: CharacterData, session: CoopSession, path: String = SaveManager.DEFAULT_PATH, tree: SkillTree = null, run_controller: DungeonRunController = null, seed: int = -1) -> bool:
	if c == null:
		return false
	if session != null:
		return true
	# Capture the in-flight dungeon run so the next launch resumes at the same
	# room with the same cleared-room state (PRD #42 / #46). When no run is in
	# flight (run_controller == null) the saved state is an empty dict, which
	# main_scene treats as "start a fresh dungeon" on resume.
	var run_state: Dictionary = {}
	if run_controller != null:
		run_state = DungeonRunSerializerRef.serialize(run_controller, seed)
	SaveManager.save(c, path, tree, null, null, null, null, run_state)
	return true
