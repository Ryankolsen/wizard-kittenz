extends GutTest

# --- RoomCodeGenerator.generate ---------------------------------------------

func test_generate_returns_five_uppercase_alphanumeric_chars():
	# Issue scenario 1: Core wiring — generate() returns 5 chars,
	# uppercase alphanumeric.
	var gen := RoomCodeGenerator.new(42)
	var code := gen.generate()
	assert_eq(code.length(), RoomCodeGenerator.CODE_LENGTH, "code length is 5")
	for c in code:
		var b := c.unicode_at(0)
		var ok := (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
		assert_true(ok, "char %s is uppercase alphanumeric" % c)

func test_generate_seeded_is_deterministic():
	var a := RoomCodeGenerator.new(123).generate()
	var b := RoomCodeGenerator.new(123).generate()
	assert_eq(a, b, "same seed -> same code")

func test_generate_different_seeds_diverge():
	# Pinned because two arbitrary seeds *could* happen to collide;
	# 1 and 2 against the trimmed charset don't.
	var a := RoomCodeGenerator.new(1).generate()
	var b := RoomCodeGenerator.new(2).generate()
	assert_ne(a, b)

func test_generate_uses_confusable_free_charset():
	# The trimmed charset is a strict subset of the validator's
	# accepted range; any generated code must validate.
	var gen := RoomCodeGenerator.new(7)
	for _i in range(20):
		var code := gen.generate()
		assert_true(RoomCodeValidator.is_valid(code), "generated %s validates" % code)
		# And specifically excludes the confusable glyphs.
		for ch in ["0", "O", "1", "I", "L"]:
			assert_false(code.contains(ch), "code %s excludes confusable %s" % [code, ch])

# --- RoomCodeValidator.is_valid ---------------------------------------------

func test_is_valid_accepts_canonical_code():
	# Issue scenario 2: is_valid("AB1C2") -> true.
	assert_true(RoomCodeValidator.is_valid("AB1C2"))

func test_is_valid_rejects_lowercase():
	# Issue scenario 2: is_valid("ab1c2") -> false.
	assert_false(RoomCodeValidator.is_valid("ab1c2"))

func test_is_valid_rejects_wrong_length():
	# Issue scenario 2: is_valid("TOOLONG") -> false.
	assert_false(RoomCodeValidator.is_valid("TOOLONG"))
	assert_false(RoomCodeValidator.is_valid("AB12"), "4 chars rejected")
	assert_false(RoomCodeValidator.is_valid(""), "empty rejected")

func test_is_valid_rejects_punctuation_and_whitespace():
	assert_false(RoomCodeValidator.is_valid("AB-12"))
	assert_false(RoomCodeValidator.is_valid("AB 12"))
	assert_false(RoomCodeValidator.is_valid("AB!12"))

func test_is_valid_rejects_mixed_case():
	assert_false(RoomCodeValidator.is_valid("Ab1C2"))

# --- LobbyState.add_player --------------------------------------------------

func test_add_player_increments_count_and_appears_in_list():
	# Issue scenario 3: add_player increases player_count by 1 and
	# the player appears in `players`.
	var ls := LobbyState.new("AB1C2")
	var p := LobbyPlayer.make("u1", "Bourbon Cat", "Mage", true)
	assert_true(ls.add_player(p))
	assert_eq(ls.player_count(), 1)
	assert_eq(ls.find_player("u1"), p, "player retrievable by id")

func test_add_player_rejects_duplicate_id():
	var ls := LobbyState.new()
	ls.add_player(LobbyPlayer.make("u1", "A", "Mage"))
	assert_false(ls.add_player(LobbyPlayer.make("u1", "A2", "Thief")), "duplicate id rejected")
	assert_eq(ls.player_count(), 1, "count unchanged on duplicate")

func test_add_player_rejects_when_full():
	var ls := LobbyState.new()
	for i in range(LobbyState.MAX_PLAYERS):
		ls.add_player(LobbyPlayer.make("u%d" % i, "K", "Mage"))
	assert_false(ls.add_player(LobbyPlayer.make("uX", "Late", "Ninja")), "full lobby rejects")
	assert_eq(ls.player_count(), LobbyState.MAX_PLAYERS)

func test_add_player_null_safe():
	var ls := LobbyState.new()
	assert_false(ls.add_player(null))
	assert_eq(ls.player_count(), 0)

func test_remove_player_drops_slot():
	var ls := LobbyState.new()
	ls.add_player(LobbyPlayer.make("u1", "A", "Mage"))
	ls.add_player(LobbyPlayer.make("u2", "B", "Thief"))
	assert_true(ls.remove_player("u1"))
	assert_eq(ls.player_count(), 1)
	assert_null(ls.find_player("u1"))

func test_remove_player_unknown_id_noop():
	var ls := LobbyState.new()
	ls.add_player(LobbyPlayer.make("u1", "A", "Mage"))
	assert_false(ls.remove_player("nope"))
	assert_eq(ls.player_count(), 1)

# --- LobbyState.can_start ---------------------------------------------------

func test_can_start_false_when_any_player_not_ready():
	# Issue scenario 4: can_start returns false when any player's
	# ready == false.
	var ls := LobbyState.new()
	var a := LobbyPlayer.make("u1", "A", "Mage", true)
	var b := LobbyPlayer.make("u2", "B", "Thief")
	a.ready = true
	b.ready = false
	ls.add_player(a)
	ls.add_player(b)
	assert_false(ls.can_start(), "one not-ready blocks start")

func test_can_start_true_when_all_ready():
	# Issue scenario 4: returns true when all players are ready.
	var ls := LobbyState.new()
	var a := LobbyPlayer.make("u1", "A", "Mage", true)
	var b := LobbyPlayer.make("u2", "B", "Thief")
	a.ready = true
	b.ready = true
	ls.add_player(a)
	ls.add_player(b)
	assert_true(ls.can_start())

func test_can_start_false_when_empty():
	var ls := LobbyState.new()
	assert_false(ls.can_start(), "empty lobby cannot start")

func test_can_start_solo_ready_passes():
	# MIN_PLAYERS = 1, so a solo host who's ready can start. Keeps the
	# lobby useful for solo "I want to crawl with my own party of 1"
	# without forcing a friend invite.
	var ls := LobbyState.new()
	var a := LobbyPlayer.make("u1", "A", "Mage", true)
	a.ready = true
	ls.add_player(a)
	assert_true(ls.can_start())

func test_can_start_host_must_also_be_ready():
	# The host's ready flag is gated the same as everyone else's —
	# no carve-out. Removes the "host forgot to ready up" footgun.
	var ls := LobbyState.new()
	var a := LobbyPlayer.make("u1", "Host", "Mage", true)
	var b := LobbyPlayer.make("u2", "Guest", "Thief")
	b.ready = true
	ls.add_player(a)
	ls.add_player(b)
	assert_false(ls.can_start(), "host not-ready blocks start")
	a.ready = true
	assert_true(ls.can_start())

# --- LobbyState.set_ready ---------------------------------------------------

func test_set_ready_toggles_player_flag():
	var ls := LobbyState.new()
	ls.add_player(LobbyPlayer.make("u1", "A", "Mage"))
	assert_true(ls.set_ready("u1", true))
	assert_true(ls.find_player("u1").ready)
	assert_false(ls.set_ready("u1", false))
	assert_false(ls.find_player("u1").ready)

func test_set_ready_unknown_id_noop():
	var ls := LobbyState.new()
	assert_false(ls.set_ready("nope", true))

# --- LobbyState.host --------------------------------------------------------

func test_host_returns_host_player():
	var ls := LobbyState.new()
	ls.add_player(LobbyPlayer.make("u1", "Guest", "Mage", false))
	var host := LobbyPlayer.make("u2", "Host", "Thief", true)
	ls.add_player(host)
	assert_eq(ls.host(), host)

func test_host_null_when_no_host():
	var ls := LobbyState.new()
	ls.add_player(LobbyPlayer.make("u1", "Guest", "Mage", false))
	assert_null(ls.host())

# --- LobbyPlayer / LobbyState round-trip ------------------------------------

func test_lobby_player_dict_round_trip():
	var p := LobbyPlayer.make("u1", "Bourbon Cat", "Mage", true)
	p.ready = true
	var rt := LobbyPlayer.from_dict(p.to_dict())
	assert_eq(rt.player_id, "u1")
	assert_eq(rt.kitten_name, "Bourbon Cat")
	assert_eq(rt.class_name_str, "Mage")
	assert_true(rt.ready)
	assert_true(rt.is_host)

func test_lobby_state_dict_round_trip():
	var ls := LobbyState.new("AB1C2")
	var a := LobbyPlayer.make("u1", "Host", "Mage", true)
	a.ready = true
	ls.add_player(a)
	ls.add_player(LobbyPlayer.make("u2", "Guest", "Thief"))
	var rt := LobbyState.from_dict(ls.to_dict())
	assert_eq(rt.room_code, "AB1C2")
	assert_eq(rt.player_count(), 2)
	assert_eq(rt.find_player("u1").kitten_name, "Host")
	assert_true(rt.find_player("u1").ready)
	assert_false(rt.find_player("u2").ready)

# --- NakamaLobby.apply_joins --------------------------------------------------

func test_apply_joins_adds_player_to_lobby_state():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	assert_eq(lobby.lobby_state.player_count(), 1)

func test_apply_joins_emits_lobby_updated():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	watch_signals(lobby)
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	assert_signal_emitted(lobby, "lobby_updated")

func test_apply_joins_skips_duplicate_user_id():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	lobby.apply_joins([{"user_id": "u1", "username": "kitty2"}])
	assert_eq(lobby.lobby_state.player_count(), 1)

func test_apply_joins_skips_local_player_id():
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "me"
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "me", "username": "myself"}])
	assert_eq(lobby.lobby_state.player_count(), 0)

func test_apply_joins_null_lobby_state_safe():
	var lobby := NakamaLobby.new()
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	assert_null(lobby.lobby_state, "lobby_state stays null — apply_joins does not create it")

# --- NakamaLobby.apply_leaves -------------------------------------------------

func test_apply_leaves_removes_player():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	lobby.apply_leaves([{"user_id": "u1"}])
	assert_eq(lobby.lobby_state.player_count(), 0)

func test_apply_leaves_emits_lobby_updated():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	watch_signals(lobby)
	lobby.apply_leaves([{"user_id": "u1"}])
	assert_signal_emitted(lobby, "lobby_updated")

# --- NakamaLobby.apply_state --------------------------------------------------

func test_apply_state_player_info_updates_kitten_name_and_class():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	lobby.apply_state(NakamaLobby.OP_PLAYER_INFO, "u1", {"kitten_name": "Biscuits", "class_name": "Mage"})
	assert_eq(lobby.lobby_state.find_player("u1").kitten_name, "Biscuits")
	assert_eq(lobby.lobby_state.find_player("u1").class_name_str, "Mage")

func test_apply_state_ready_toggle_sets_ready_flag():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	lobby.apply_state(NakamaLobby.OP_READY_TOGGLE, "u1", {"ready": true})
	assert_true(lobby.lobby_state.find_player("u1").ready)

func test_apply_state_start_match_emits_match_started():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_START_MATCH, "u1", {})
	assert_signal_emitted(lobby, "match_started")

func test_apply_state_unknown_opcode_noop():
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("AB1C2")
	lobby.apply_joins([{"user_id": "u1", "username": "kitty"}])
	lobby.apply_state(99, "u1", {})  # should not crash
	assert_eq(lobby.lobby_state.player_count(), 1)
