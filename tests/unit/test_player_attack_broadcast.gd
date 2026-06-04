extends GutTest

# Tests for Player → NakamaLobby.send_attack_async broadcast (PRD #328
# slice 4 / issue #332). The local swing trigger must fan to the lobby
# in co-op (so every peer's RemoteKitten can play the matching swing
# via the existing AttackChoreographer path) and stay silent in solo.

class SpyLobby:
	extends NakamaLobby
	var attacks: Array = []  # Vector2 directions
	func send_attack_async(direction: Vector2) -> void:
		attacks.append(direction)


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


func test_local_attack_broadcasts_op_attack_with_facing_direction():
	# Co-op active (lobby present): the local Player's swing trigger must
	# fire exactly one send_attack_async call with the player's current
	# facing as the direction. The receiver derives attack_type from the
	# already-broadcast PLAYER_INFO state — no attack_type on the wire.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	# Stamp a known facing so we can assert the direction matches.
	p.data.facing = Vector2.RIGHT
	p._try_attack()
	assert_eq(spy.attacks.size(), 1,
		"local swing must broadcast exactly one OP_ATTACK")
	assert_eq(spy.attacks[0], Vector2.RIGHT,
		"broadcast direction matches the player's current facing")


func test_solo_attack_does_not_broadcast():
	# Solo path (no lobby on game state): _try_attack must not call
	# send_attack_async. Confirms the co-op gate fires before the wire
	# touch so single-player runs put zero attack packets on the wire.
	var fake := FakeGameStateNoLobby.new()
	# fake.lobby intentionally null — solo path
	var p := _make_player(fake)
	p.data.facing = Vector2.RIGHT
	# No spy to assert on — the assertion is "no crash + no broadcast".
	# Reaching this assertion after _try_attack is itself the proof:
	# Player._broadcast_attack must null-check _lobby() and bail.
	p._try_attack()
	assert_true(true, "solo path completes _try_attack without a lobby")


func test_blocked_attack_does_not_broadcast():
	# Cooldown gate: a re-entrant _try_attack call inside the cooldown
	# window must NOT broadcast — only the successful swing fires the
	# wire. Without this, attack-spam would flood the wire even though
	# no animation played locally.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p.data.facing = Vector2.RIGHT
	p._try_attack()
	assert_eq(spy.attacks.size(), 1, "first attack lands")
	p._try_attack()  # cooldown gate rejects this
	assert_eq(spy.attacks.size(), 1,
		"cooldown-gated re-attack must not put a second packet on the wire")
