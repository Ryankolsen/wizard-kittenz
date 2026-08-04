extends GutTest

# Tests for the VFX half of issue #450: Player connects to
# GameState.achievement_service.achievement_unlocked and replays the
# level-up celebration with "NEW ACHIEVEMENT!" text instead of "LEVEL UP!".
#
# GameState.achievement_service is a single, per-client, account-wide
# instance (scripts/core/game_state.gd) — record_event only ever fires
# locally for events this client itself triggers (no co-op broadcast
# exists for achievements). Because each client only ever instances its
# own Player node (remote peers render via RemotePlayerInterpolator, not
# Player.gd), connecting directly here already satisfies the "only the
# unlocking player's cat, not broadcast" acceptance criterion with no
# networking plumbing, unlike the co-op XP level-up path.

class FakeGameState:
	var local_player_id: String = "me"
	var coop_session = null
	var lobby = null
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()
	var achievement_service: AchievementService = AchievementService.new(AccountSaveData.new())


class SpyLevelUpEffect extends LevelUpEffect:
	var calls: Array = []  # [new_level, text_override] pairs
	func play(new_level: int = 0, text_override: String = "") -> void:
		calls.append([new_level, text_override])


func _make_player(fake) -> Player:
	fake.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	p._inject_game_state(fake)
	add_child_autofree(p)
	return p


func test_achievement_unlock_plays_effect_with_override_text():
	var fake := FakeGameState.new()
	var p := _make_player(fake)
	var spy := SpyLevelUpEffect.new()
	p._level_up_effect = spy
	fake.achievement_service.achievement_unlocked.emit("rename_cat")
	assert_eq(spy.calls.size(), 1, "one achievement unlock plays the effect exactly once")
	assert_eq(spy.calls[0][1], "NEW ACHIEVEMENT!",
		"achievement unlocks swap in \"NEW ACHIEVEMENT!\" text instead of \"LEVEL UP!\"")


func test_achievement_unlock_does_nothing_without_level_up_effect_node():
	# Defensive: a Player with no LevelUpEffect child (e.g. a bare test
	# double) must not crash when an achievement unlocks.
	var fake := FakeGameState.new()
	var p := _make_player(fake)
	p._level_up_effect = null
	fake.achievement_service.achievement_unlocked.emit("rename_cat")
	assert_true(true, "no crash with a null level-up effect")


func test_multiple_unlocks_each_replay_the_effect():
	var fake := FakeGameState.new()
	var p := _make_player(fake)
	var spy := SpyLevelUpEffect.new()
	p._level_up_effect = spy
	fake.achievement_service.achievement_unlocked.emit("rename_cat")
	fake.achievement_service.achievement_unlocked.emit("enter_dungeon")
	assert_eq(spy.calls.size(), 2, "each distinct unlock replays its own celebration burst")
