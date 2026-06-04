extends GutTest

# Tests for Player → NakamaLobby.send_damage_dealt_async broadcast (PRD
# #328 slice 6, issue #334). The local damage-applied site must fan to
# the lobby in co-op (so every peer's RemoteDamageVisualizer spawns the
# matching FloatingText overlay) and stay silent in solo.
#
# The damage-applied site itself (inside _apply_melee_damage /
# _apply_spell_basic_damage / _apply_spell_effect) is exercised
# end-to-end by the existing damage tests; this test pins the broadcast
# seam directly via _broadcast_damage so we don't need a live hitbox
# overlap fixture to validate the wire path.

class SpyLobby:
	extends NakamaLobby
	var damages: Array = []  # [enemy_id, damage] pairs
	func send_damage_dealt_async(enemy_id: String, damage: int) -> void:
		damages.append([enemy_id, damage])


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


func test_broadcast_damage_emits_single_packet_in_coop():
	# Co-op active (lobby present): _broadcast_damage must call
	# send_damage_dealt_async with the enemy_id and damage value.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p._broadcast_damage("e3", 12)
	assert_eq(spy.damages.size(), 1, "exactly one OP_DAMAGE_DEALT broadcast")
	assert_eq(spy.damages[0][0], "e3", "enemy_id matches the hit target")
	assert_eq(spy.damages[0][1], 12, "damage matches DamageResolver's dealt value")


func test_solo_broadcast_damage_does_not_crash():
	# Solo path (no lobby on game state): _broadcast_damage must not
	# touch the wire and must not crash. The solo damage path still
	# spawns the local FloatingText overlay independently.
	var fake := FakeGameStateNoLobby.new()
	# fake.lobby intentionally null — solo path
	var p := _make_player(fake)
	p._broadcast_damage("e3", 12)
	assert_true(true, "solo _broadcast_damage completes without a lobby")


func test_broadcast_damage_with_empty_enemy_id_gated_at_send():
	# An enemy without a stable id (pre-spawn-layer / test fixture)
	# arriving at the broadcast hook still gets gated downstream — the
	# spy's override doesn't trigger the gate, but we pin the contract
	# that the call is made and let send_damage_dealt_async's own guard
	# (test_send_damage_dealt_async_empty_enemy_id_safe) drop it.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p._broadcast_damage("", 5)
	# Spy records the call (the real send-side guard would drop it on the
	# wire — covered in test_nakama_lobby_damage.gd). The seam contract
	# here is: Player asks; lobby gates.
	assert_eq(spy.damages.size(), 1, "Player delegates the gate decision to the lobby")
	assert_eq(spy.damages[0][0], "", "empty id passed through; lobby-side guard drops it")
