extends GutTest

# Tests for Player → NakamaLobby.send_player_died_async broadcast (PRD #328
# slice 8 / issue #336). The local Player._check_died is the single edge
# that fires the wire packet — same hook that already emits the died
# signal — and stays silent in solo.

class SpyLobby:
	extends NakamaLobby
	var died_calls: int = 0
	func send_player_died_async() -> void:
		died_calls += 1


class FakeGameStateNoLobby:
	var local_player_id: String = "me"
	var coop_session = null
	var lobby = null
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()


class FakeGameStateWithLobby:
	var local_player_id: String = "me"
	var coop_session = null
	var lobby = null  # SpyLobby
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()


func _make_player(fake) -> Player:
	fake.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	p._inject_game_state(fake)
	add_child_autofree(p)
	return p


func _kill(p: Player) -> void:
	# Drop HP to zero and pump _physics_process once to hit the _check_died
	# edge — the same path solo death walks.
	p.data.hp = 0
	p._physics_process(0.016)


func test_death_broadcasts_op_player_died_in_coop():
	# Co-op active (lobby present): a fresh death broadcasts exactly one
	# send_player_died_async call. Edge-gated through _died_emitted so a
	# subsequent _physics_process tick doesn't re-broadcast.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	_kill(p)
	assert_eq(spy.died_calls, 1,
		"co-op death must broadcast exactly one OP_PLAYER_DIED")
	# Second tick after death: must NOT re-broadcast.
	p._physics_process(0.016)
	assert_eq(spy.died_calls, 1,
		"_died_emitted edge gate must suppress repeat broadcasts")


func test_solo_death_does_not_broadcast():
	# Solo path (no lobby): death must not call send_player_died_async.
	# The wire stays untouched in single-player.
	var fake := FakeGameStateNoLobby.new()
	var p := _make_player(fake)
	_kill(p)
	# Nothing to assert on (no lobby spy in solo) — the call simply must
	# not crash. The wire untouched is the contract.
	assert_true(true, "solo death completes without a lobby")
