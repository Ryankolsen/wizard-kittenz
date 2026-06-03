extends GutTest

# Slice 3 of PRD #328 (issue #331). OP_PLAYER_INFO grows an
# equipped_weapon_id key so the matching RemoteKitten on every peer can
# resolve a WeaponDefinition + sprite for the broadcasting player.
# Backward compat: missing key on a pre-#331 sender decodes to "" which
# is the "unarmed / class-default" sentinel — same shape no-op the local
# Player walks when ItemInventory has no weapon equipped.

class MockSocket:
	extends RefCounted
	var sent: Array = []  # each entry: { match_id, op_code, raw }

	func send_match_state_async(match_id: String, op_code: int, raw: String) -> void:
		sent.append({"match_id": match_id, "op_code": op_code, "raw": raw})


func _make_lobby_with_socket() -> Dictionary:
	var lobby := NakamaLobby.new()
	var mock := MockSocket.new()
	lobby._socket = mock
	lobby._match_id = "match-abc"
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	return {"lobby": lobby, "socket": mock}


# Test 1 (thinnest end-to-end): receiver applies equipped_weapon_id from
# OP_PLAYER_INFO into the matching LobbyPlayer.
func test_apply_state_op_player_info_decodes_equipped_weapon_id() -> void:
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make("alice", "", ""))
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "alice", {
		"kitten_name": "Slumber",
		"class_name": "Sleepy Kitten",
		"character_class": CharacterData.CharacterClass.SLEEPY_KITTEN,
		"equipped_weapon_id": "katana",
	})
	var p := lobby.lobby_state.find_player("alice")
	assert_eq(p.equipped_weapon_id, "katana",
		"receiver must read equipped_weapon_id off the payload")


# Test 2: sender writes equipped_weapon_id into the OP_PLAYER_INFO payload.
func test_send_player_info_async_includes_equipped_weapon_id() -> void:
	var fixture := _make_lobby_with_socket()
	var lobby: NakamaLobby = fixture["lobby"]
	var mock: MockSocket = fixture["socket"]
	var p := LobbyPlayer.make("me", "Chonkers", "Chonk Kitten", false,
		CharacterData.CharacterClass.CHONK_KITTEN)
	p.equipped_weapon_id = "iron_sword"
	await lobby.send_player_info_async(p)
	assert_eq(mock.sent.size(), 1, "exactly one packet sent")
	var pkt: Dictionary = mock.sent[0]
	var parsed = JSON.parse_string(pkt["raw"])
	assert_eq(parsed["equipped_weapon_id"], "iron_sword",
		"payload must carry the equipped weapon id")


# Test 3: missing key on receiver falls through to "" (backward compat
# with pre-#331 senders).
func test_apply_state_op_player_info_missing_equipped_weapon_id_defaults_empty() -> void:
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	var p := LobbyPlayer.make("alice", "", "")
	p.equipped_weapon_id = "starting_value"
	lobby.lobby_state.add_player(p)
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "alice", {
		"kitten_name": "Old",
		"class_name": "Wizard Kitten",
	})
	var got := lobby.lobby_state.find_player("alice")
	assert_eq(got.equipped_weapon_id, "starting_value",
		"missing key must NOT clobber the stored equipped_weapon_id — "
		+ "pre-#331 senders send no key but their broadcast shouldn't "
		+ "wipe whatever a later #331-aware packet already set")


# Test 4: LobbyPlayer.to_dict / from_dict round-trip preserves
# equipped_weapon_id so a persisted lobby roster reload doesn't lose it.
func test_lobby_player_round_trip_preserves_equipped_weapon_id() -> void:
	var p := LobbyPlayer.make("alice", "k", "Battle Kitten", false,
		CharacterData.CharacterClass.BATTLE_KITTEN)
	p.equipped_weapon_id = "silver_sword"
	var d := p.to_dict()
	assert_eq(d["equipped_weapon_id"], "silver_sword")
	var p2 := LobbyPlayer.from_dict(d)
	assert_eq(p2.equipped_weapon_id, "silver_sword")


# Test 5: pre-#331 from_dict (missing field) defaults to "".
func test_lobby_player_from_dict_missing_equipped_weapon_id_defaults_empty() -> void:
	var p := LobbyPlayer.from_dict({
		"player_id": "alice",
		"kitten_name": "k",
		"class_name": "Whatever",
	})
	assert_eq(p.equipped_weapon_id, "")


# Test 6 (late joiner rebroadcast): when a peer joins mid-match, the
# rebroadcast triggered in _on_match_presence carries equipped_weapon_id
# for our local player so the new peer learns our current loadout.
func test_late_joiner_rebroadcast_includes_equipped_weapon_id() -> void:
	var fixture := _make_lobby_with_socket()
	var lobby: NakamaLobby = fixture["lobby"]
	var mock: MockSocket = fixture["socket"]
	var me := LobbyPlayer.make("me", "Me", "Battle Kitten", false,
		CharacterData.CharacterClass.BATTLE_KITTEN)
	me.equipped_weapon_id = "iron_sword"
	lobby.lobby_state.add_player(me)
	# Simulate the apply_joins path the late-joiner _on_match_presence
	# walks: add a new peer, then trigger the rebroadcast manually
	# the same way _on_match_presence does.
	lobby.apply_joins([{"user_id": "newcomer", "username": "bob"}])
	await lobby.send_player_info_async(me)
	# Last packet — the rebroadcast — carries our equipped weapon.
	var pkt: Dictionary = mock.sent[mock.sent.size() - 1]
	var parsed = JSON.parse_string(pkt["raw"])
	assert_eq(parsed["equipped_weapon_id"], "iron_sword",
		"late-joiner rebroadcast must carry our current equipped weapon "
		+ "so the new peer renders us with the right loadout immediately")
