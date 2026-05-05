extends Node

var current_character: CharacterData = null
var skill_tree: SkillTree = null
# Lifetime stats used by UnlockRegistry to evaluate gates. Always non-null
# after _ready so call sites can read freely; a fresh tracker (everything
# zero) is the right default for a brand-new save.
var meta_tracker: MetaProgressionTracker = MetaProgressionTracker.new()
var unlock_registry: UnlockRegistry = UnlockRegistry.make_default()
# Revive token balance. Always non-null so call sites (Player on death,
# future death-screen UI) can read .count freely without a null check.
var token_inventory: TokenInventory = TokenInventory.new()
# XP earned in the solo path since the last server sync. Always non-null
# so the kill flow / save layer can read .pending_xp freely without a
# null check. Hydrated from KittenSaveData.offline_xp_earned on load;
# the sync orchestrator (post-#14) calls clear() after a successful
# OfflineProgressMerger.merge_xp.
var offline_xp_tracker: OfflineXPTracker = OfflineXPTracker.new()
# Active co-op session. Non-null only between the lobby's Start Match
# handler and session end (player back-out / dungeon failed). Player.gd's
# kill flow null-checks this to branch between solo (apply XP locally)
# and co-op (broadcast XP via session.xp_broadcaster). Sourced from the
# lobby UI once #16 lands; default null preserves the solo behavior on
# fresh-install / no-multiplayer paths.
var coop_session: CoopSession = null
# This client's player_id within an active co-op session. Sourced from
# AccountManager once Google Play Games auth (#15 follow-up) lands;
# default empty string keeps the solo branch firing until co-op is
# wired. Stored on GameState (not just CoopSession) so it survives
# across sessions (multiple matches in a row, lobby reconstruction)
# and so a single source of truth reads from AccountManager.
var local_player_id: String = ""

func _ready() -> void:
	_try_load_save()

func _try_load_save() -> void:
	var save_data := SaveManager.load()
	if save_data == null:
		return
	var c := CharacterData.new()
	save_data.apply_to(c)
	current_character = c
	skill_tree = _build_tree_for(c)
	skill_tree.apply_unlocked_ids(save_data.unlocked_skill_ids)
	meta_tracker = save_data.to_tracker()
	token_inventory = save_data.to_inventory()
	offline_xp_tracker = save_data.to_offline_xp_tracker()

func set_character(c: CharacterData) -> void:
	current_character = c
	skill_tree = _build_tree_for(c)

func clear() -> void:
	current_character = null
	skill_tree = null
	meta_tracker = MetaProgressionTracker.new()
	token_inventory = TokenInventory.new()
	offline_xp_tracker = OfflineXPTracker.new()
	# Tear down any live co-op session before dropping the reference so
	# the per-run managers unbind cleanly and don't keep handing XP to
	# a member.real_stats that's about to be replaced.
	if coop_session != null and coop_session.is_active():
		coop_session.end()
	coop_session = null
	local_player_id = ""

# Per-class tree builder. Each class gets its own factory so unlocks on one
# class's tree never bleed into another's (independent-trees acceptance
# criterion from #10). Unknown class falls through to the mage tree as a safe
# default — better than returning null and forcing every call site to
# null-check.
func _build_tree_for(c: CharacterData) -> SkillTree:
	match c.character_class:
		CharacterData.CharacterClass.MAGE: return SkillTree.make_mage_tree()
		CharacterData.CharacterClass.THIEF: return SkillTree.make_thief_tree()
		CharacterData.CharacterClass.NINJA: return SkillTree.make_ninja_tree()
		CharacterData.CharacterClass.ARCHMAGE: return SkillTree.make_mage_tree()
	return SkillTree.make_mage_tree()
