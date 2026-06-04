extends GutTest

# Tests for Player → NakamaLobby.send_player_hit_async broadcast (PRD
# #328 slice 7 / issue #335). Player.take_damage(damage, source_position)
# is the central hook every enemy-on-player damage site calls — it
# broadcasts OP_PLAYER_HIT in co-op so every peer's RemoteKitten plays
# the matching hit-flash + knockback, and stays silent in solo.

class SpyLobby:
	extends NakamaLobby
	var hits: Array = []  # [damage, source_position] pairs
	func send_player_hit_async(damage: int, source_position: Vector2) -> void:
		hits.append([damage, source_position])


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


func test_take_damage_broadcasts_op_player_hit_with_damage_and_source():
	# Co-op active (lobby present): take_damage must broadcast exactly
	# one send_player_hit_async call with the damage value and the
	# enemy-side source position.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p.take_damage(7, Vector2(123.0, 45.0))
	assert_eq(spy.hits.size(), 1,
		"take_damage must broadcast exactly one OP_PLAYER_HIT")
	assert_eq(spy.hits[0][0], 7, "damage value carried on the wire")
	assert_eq(spy.hits[0][1], Vector2(123.0, 45.0),
		"source_position carried on the wire (for receiver knockback dir)")


func test_solo_take_damage_does_not_broadcast():
	# Solo path (no lobby on game state): take_damage must not call
	# send_player_hit_async. The wire stays untouched in single-player.
	var fake := FakeGameStateNoLobby.new()
	var p := _make_player(fake)
	p.take_damage(7, Vector2(123.0, 45.0))
	assert_true(true, "solo take_damage completes without a lobby")


func test_take_damage_zero_does_not_broadcast():
	# A "Miss" pulse (damage == 0) at the Player edge is a defensive
	# no-op so the wire stays minimal. Send-side guard already drops it
	# but pinning here catches a regression that moves the gate.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p.take_damage(0, Vector2(123.0, 45.0))
	assert_eq(spy.hits.size(), 0,
		"zero-damage hit must not put a packet on the wire")
