extends GutTest

# Tests for NakamaLobby OP_PLAYER_INFO carrying character_class (issue #170).
# The payload must include character_class on send and decode safely on
# receive — including the backwards-compatible default when an older client
# sends a payload without the field.

class MockSocket:
	extends RefCounted
	var sent: Array = []  # each entry: { match_id, op_code, raw }

	func send_match_state_async(match_id: String, op_code: int, raw: String) -> void:
		sent.append({"match_id": match_id, "op_code": op_code, "raw": raw})


func _make_lobby_with_socket() -> Dictionary:
	var lobby := NakamaLobby.new()
	# Reach in: NakamaLobby keeps _socket as untyped, set via _init. We pin
	# _match_id directly so send_player_info_async clears its "no match" guard.
	var mock := MockSocket.new()
	lobby._socket = mock
	lobby._match_id = "match-abc"
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	return {"lobby": lobby, "socket": mock}


func test_send_player_info_async_includes_character_class():
	# Issue #170 acceptance: outbound PLAYER_INFO carries the raw enum int.
	var fixture := _make_lobby_with_socket()
	var lobby: NakamaLobby = fixture["lobby"]
	var mock: MockSocket = fixture["socket"]
	var p := LobbyPlayer.make("me", "Chonkers", "Chonk Kitten", false,
		CharacterData.CharacterClass.CHONK_KITTEN)
	await lobby.send_player_info_async(p)
	assert_eq(mock.sent.size(), 1, "exactly one packet sent")
	var pkt: Dictionary = mock.sent[0]
	assert_eq(pkt["op_code"], NakamaLobby.OP_PLAYER_INFO)
	var parsed = JSON.parse_string(pkt["raw"])
	assert_eq(parsed["character_class"], CharacterData.CharacterClass.CHONK_KITTEN,
		"payload must include the raw enum int for character_class")
	assert_eq(parsed["kitten_name"], "Chonkers")
	assert_eq(parsed["class_name"], "Chonk Kitten")


func test_apply_state_op_player_info_decodes_character_class():
	# Receiver side: a fresh PLAYER_INFO updates character_class_int.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make("alice", "", ""))
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "alice", {
		"kitten_name": "Slumber",
		"class_name": "Sleepy Kitten",
		"character_class": CharacterData.CharacterClass.SLEEPY_KITTEN,
	})
	var p := lobby.lobby_state.find_player("alice")
	assert_eq(p.character_class_int, CharacterData.CharacterClass.SLEEPY_KITTEN,
		"receiver must read character_class off the payload")


func test_apply_state_op_player_info_missing_character_class_defaults_wizard_kitten():
	# Issue #170 acceptance: backwards-compat — a payload without the new
	# field must not crash and must leave the player at the WIZARD_KITTEN
	# default (matches LobbyPlayer.make default).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make("alice", "", ""))
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "alice", {
		"kitten_name": "Old",
		"class_name": "Wizard Kitten",
	})
	var p := lobby.lobby_state.find_player("alice")
	assert_eq(p.character_class_int, CharacterData.CharacterClass.WIZARD_KITTEN,
		"missing character_class falls back to the wizard default")


func test_apply_state_op_player_info_creates_player_when_presence_not_applied_yet():
	# Regression (#337 follow-up): a joiner's PLAYER_INFO can reach an
	# existing peer BEFORE the match-presence join event has added that
	# joiner to the roster (Nakama doesn't order presence vs match-state
	# delivery). The old handler did find_player(sender_id) → null → drop,
	# so once apply_joins later added the joiner at the WIZARD_KITTEN
	# default, the class was never corrected and the teammate rendered with
	# the wrong (default) sprite. The handler must instead create the roster
	# entry from the payload so the carried class survives out-of-order
	# delivery. apply_joins skips duplicates, so the later presence event
	# won't clobber it.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make("me", "Me", "Wizard Kitten"))
	# alice is NOT in the roster yet — her presence-join hasn't arrived.
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "alice", {
		"kitten_name": "Battlecat",
		"class_name": "Battle Kitten",
		"character_class": CharacterData.CharacterClass.BATTLE_KITTEN,
		"equipped_weapon_id": "iron_sword",
	})
	var p := lobby.lobby_state.find_player("alice")
	assert_not_null(p, "PLAYER_INFO must create the roster entry when the "
		+ "presence-join hasn't been applied yet")
	assert_eq(p.character_class_int, CharacterData.CharacterClass.BATTLE_KITTEN,
		"the carried class must survive out-of-order delivery")
	assert_eq(p.kitten_name, "Battlecat")
	assert_eq(p.equipped_weapon_id, "iron_sword")


func test_apply_state_op_player_info_does_not_fabricate_self_entry():
	# Defensive: a self-echo (sender_id == local_player_id) that arrives
	# while we somehow have no roster entry must NOT fabricate a ghost local
	# player (which would carry is_host=false and duplicate the seeded self).
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "me", {
		"kitten_name": "Me",
		"character_class": CharacterData.CharacterClass.CHONK_KITTEN,
	})
	assert_null(lobby.lobby_state.find_player("me"),
		"self PLAYER_INFO must not fabricate a local roster entry")


func test_send_player_info_async_includes_is_host():
	# Issue #352: outbound PLAYER_INFO must carry is_host so a joiner learns
	# who the party host is. Without it the guest's roster marks everyone
	# is_host=false → lobby_state.host() returns null → the host-authoritative
	# routers (boss-cleared / dungeon-transition / advance-floor) drop every
	# packet on the guest.
	var fixture := _make_lobby_with_socket()
	var lobby: NakamaLobby = fixture["lobby"]
	var mock: MockSocket = fixture["socket"]
	var host := LobbyPlayer.make("me", "Hostcat", "Mage", true)
	await lobby.send_player_info_async(host)
	var parsed = JSON.parse_string(mock.sent[0]["raw"])
	assert_true(parsed["is_host"], "host's PLAYER_INFO must carry is_host=true")


func test_apply_state_op_player_info_decodes_is_host_so_host_resolves():
	# Receiver side (#352): the host's PLAYER_INFO marks the roster entry as
	# host, so lobby_state.host() resolves to it. apply_joins seeded the host
	# entry with is_host=false (LobbyPlayer.make default), so this packet is
	# what flips it.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make("me", "Me", "Wizard Kitten"))
	# the host, as apply_joins would have added it: non-host placeholder.
	lobby.lobby_state.add_player(LobbyPlayer.make("host-1", "", "", false))
	assert_null(lobby.lobby_state.host(), "host unknown until PLAYER_INFO arrives")
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "host-1", {
		"kitten_name": "Hostcat",
		"class_name": "Mage",
		"is_host": true,
	})
	var h := lobby.lobby_state.host()
	assert_not_null(h, "host() must resolve once the host's PLAYER_INFO lands")
	assert_eq(h.player_id, "host-1")


func test_apply_state_op_player_info_creates_host_entry_when_presence_not_applied():
	# Out-of-order delivery (#352 × #337): the host's PLAYER_INFO can reach a
	# joiner before apply_joins adds the host. The created roster entry must
	# carry is_host from the payload so host() resolves immediately.
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make("me", "Me", "Wizard Kitten"))
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "host-1", {
		"kitten_name": "Hostcat",
		"class_name": "Mage",
		"is_host": true,
	})
	var h := lobby.lobby_state.host()
	assert_not_null(h, "PLAYER_INFO must create a host entry on out-of-order delivery")
	assert_eq(h.player_id, "host-1")


func test_apply_state_op_player_info_missing_is_host_preserves_stored():
	# Backwards-compat: a pre-#352 sender omits is_host. The stored flag must
	# survive so an is_host already learned from another packet isn't clobbered.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	lobby.lobby_state.add_player(LobbyPlayer.make("host-1", "", "Mage", true))
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "host-1", {
		"kitten_name": "Hostcat",
		"class_name": "Mage",
	})
	assert_true(lobby.lobby_state.find_player("host-1").is_host,
		"missing is_host must not clobber the stored host flag")


func test_lobby_player_round_trip_preserves_character_class():
	# Defensive: from_dict(to_dict(x)).character_class_int == x.character_class_int
	# so a persisted lobby roster reload doesn't lose class selection.
	var p := LobbyPlayer.make("alice", "k", "Battle Kitten", false,
		CharacterData.CharacterClass.BATTLE_KITTEN)
	var d := p.to_dict()
	assert_eq(d["character_class"], CharacterData.CharacterClass.BATTLE_KITTEN)
	var p2 := LobbyPlayer.from_dict(d)
	assert_eq(p2.character_class_int, CharacterData.CharacterClass.BATTLE_KITTEN)


func test_lobby_player_from_dict_missing_field_defaults_wizard_kitten():
	# Pre-#170 saves / packets won't carry the field — they must still
	# parse, and default to wizard kitten.
	var p := LobbyPlayer.from_dict({
		"player_id": "alice",
		"kitten_name": "k",
		"class_name": "Whatever",
	})
	assert_eq(p.character_class_int, CharacterData.CharacterClass.WIZARD_KITTEN)
