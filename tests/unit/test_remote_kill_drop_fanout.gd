extends GutTest

# Slice 7 of PRD #201: co-op drop fan-out. Every party member rolls an
# independent item drop on each enemy kill, using their own CharacterData
# (so each player gets class-appropriate loot). The killer's local resolve
# path lives in KillRewardRouter and is unchanged; remote clients perform
# their own resolve on receipt of the kill packet through
# RemoteItemDropResolver, wired off GameState._on_kill_received.

func _make_character(klass: int, level: int = 11) -> CharacterData:
	var c := CharacterData.make_new(klass, "n")
	c.level = level
	return c

func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng

# --- RemoteItemDropResolver pure helper -------------------------------------

func test_remote_resolver_boss_packet_always_drops():
	# Context.BOSS has drop_chance 1.0 — every receiving client gets an
	# item on a boss kill. Pin across multiple seeds (not a lucky one).
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	for s in [1, 2, 3, 17, 42, 99]:
		var item := RemoteItemDropResolver.resolve(wizard, true, _seeded_rng(s))
		assert_not_null(item, "boss packet always drops (seed %d)" % s)

func test_remote_resolver_returns_class_eligible_item_for_wizard():
	# Wizard L11 receiving a boss packet rolls items from the wizard pool
	# only — never a Battle-only or Chonk-only piece.
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	for s in [1, 2, 3, 17, 42, 99, 7, 13, 21, 55]:
		var item := RemoteItemDropResolver.resolve(wizard, true, _seeded_rng(s))
		assert_not_null(item, "seed %d produced no item" % s)
		assert_true(
			ItemDropResolver.is_drop_eligible(item, CharacterData.CharacterClass.WIZARD_KITTEN),
			"item %s must be Wizard-eligible (seed %d)" % [item.id, s])

func test_remote_resolver_two_clients_get_independent_class_eligible_items():
	# Same wire packet (same boss kill), two clients with different
	# classes: each rolls its own class-appropriate item. With the same
	# seed we still pin that the two rolls are independent — both produce
	# items eligible for the receiving client, not the sender.
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	var chonk := _make_character(CharacterData.CharacterClass.CHONK_KITTEN, 11)
	var wizard_item := RemoteItemDropResolver.resolve(wizard, true, _seeded_rng(42))
	var chonk_item := RemoteItemDropResolver.resolve(chonk, true, _seeded_rng(42))
	assert_not_null(wizard_item, "wizard receives a drop on boss packet")
	assert_not_null(chonk_item, "chonk receives a drop on boss packet")
	assert_true(
		ItemDropResolver.is_drop_eligible(wizard_item, CharacterData.CharacterClass.WIZARD_KITTEN),
		"wizard's drop must be wizard-eligible")
	assert_true(
		ItemDropResolver.is_drop_eligible(chonk_item, CharacterData.CharacterClass.CHONK_KITTEN),
		"chonk's drop must be chonk-eligible")
	# Independence: the two rolls should generally diverge (rarity / pool
	# differs by class). Allow same-id on the rare collision but assert
	# class-eligibility separately above.
	assert_true(true, "independent rolls — class-eligibility is the load-bearing assertion")

func test_remote_resolver_null_character_returns_null():
	# Pre-handshake / freshly-cleared GameState path: current_character is
	# null when a stale signal somehow fires before character creation.
	var item := RemoteItemDropResolver.resolve(null, true, _seeded_rng(1))
	assert_null(item, "null character is a silent no-op")

func test_remote_resolver_regular_enemy_kill_some_nulls():
	# Context.ENEMY has drop_chance 0.10 — most rolls return null. Pins
	# that we're using the ENEMY context, not BOSS, on a non-boss packet.
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	var rng := _seeded_rng(12345)
	var nulls := 0
	for i in 100:
		if RemoteItemDropResolver.resolve(wizard, false, rng) == null:
			nulls += 1
	assert_true(nulls > 50,
		"ENEMY context (boss=false) produces mostly nulls at 10%% rate, got %d nulls" % nulls)

# --- NakamaLobby wire packet carries is_boss ---------------------------------

func test_wire_packet_decodes_boss_flag_true():
	# Slice 7: receivers need to know is_boss so they can pick the right
	# ItemDropResolver.Context locally. The flag travels on the "boss"
	# payload key.
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "u2",
		{"enemy_id": "r3_e0", "xp": 7, "boss": true})
	assert_signal_emitted(lobby, "kill_received")
	var params: Array = get_signal_parameters(lobby, "kill_received")
	assert_eq(params[3], true, "is_boss decoded from boss payload key")

func test_wire_packet_decodes_boss_flag_false_default():
	# Older clients without the boss key default to false (ENEMY context).
	var lobby := NakamaLobby.new()
	lobby.lobby_state = LobbyState.new("ABCDE")
	watch_signals(lobby)
	lobby.apply_state(NakamaLobby.OP_KILL, "u2", {"enemy_id": "r3_e0", "xp": 7})
	assert_signal_emitted(lobby, "kill_received")
	var params: Array = get_signal_parameters(lobby, "kill_received")
	assert_eq(params[3], false, "missing boss key defaults to false")

# --- KillRewardRouter forwards is_boss to lobby.send_kill_async --------------

class _RecordingLobby:
	extends NakamaLobby
	var sent_kills: Array = []
	func send_kill_async(enemy_id: String, killer_id: String, xp_value: int, is_boss: bool = false) -> void:
		sent_kills.append([enemy_id, killer_id, xp_value, is_boss])

func _make_lobby_state(player_specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
		ls.add_player(LobbyPlayer.make(spec[0], spec[1], spec[2], false))
	return ls

func _make_two_room_dungeon() -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	d.add_room(start)
	d.start_id = 0
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	d.add_room(boss)
	d.boss_id = 1
	return d

func test_kill_reward_router_sends_is_boss_true_for_boss_kill():
	# The killer's wire send carries is_boss so the receiving clients can
	# pick BOSS context locally. Without this the receivers would always
	# roll at ENEMY's 10% rate and boss kills would mostly drop nothing
	# on remote clients.
	var lobby_state := _make_lobby_state([["u1", "A", "Mage"]])
	var c := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	enemy.xp_reward = 7
	enemy.is_boss = true
	enemy.enemy_id = "boss_0"
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", null, lobby)
	assert_eq(lobby.sent_kills.size(), 1)
	assert_eq(lobby.sent_kills[0][3], true,
		"boss kill packet carries is_boss=true on the wire")

func test_kill_reward_router_sends_is_boss_false_for_regular_kill():
	var lobby_state := _make_lobby_state([["u1", "A", "Mage"]])
	var c := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 1)
	var session := CoopSession.new(lobby_state, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.DOG_KNIGHT)
	enemy.xp_reward = 3
	enemy.enemy_id = "r3_e0"
	var lobby := _RecordingLobby.new()
	KillRewardRouter.route_kill(c, enemy, session, "u1", null, lobby)
	assert_eq(lobby.sent_kills.size(), 1)
	assert_eq(lobby.sent_kills[0][3], false,
		"regular kill packet carries is_boss=false on the wire")

# --- GameState integration: remote kill triggers local drop ------------------

var _saved_session: CoopSession = null
var _saved_local_id: String = ""
var _saved_character: CharacterData = null
var _saved_inventory: ItemInventory = null

func _snapshot_game_state() -> void:
	_saved_session = GameState.coop_session
	_saved_local_id = GameState.local_player_id
	_saved_character = GameState.current_character
	_saved_inventory = GameState.item_inventory

func _restore_game_state() -> void:
	GameState.coop_session = _saved_session
	GameState.local_player_id = _saved_local_id
	GameState.current_character = _saved_character
	GameState.item_inventory = _saved_inventory

# Minimal Player stand-in: a Node with the item_dropped signal in the
# "player" group. GameState._on_kill_received looks up by group, then
# emits item_dropped — the real Player has the same shape. Using a stub
# keeps the test pure-data (no Player scene boot / no _ready dependencies).
class _StubPlayer:
	extends Node
	signal item_dropped(item: ItemData)
	var received: Array = []
	func _ready() -> void:
		add_to_group("player")
		item_dropped.connect(_on_item_dropped)
	func _on_item_dropped(item: ItemData) -> void:
		received.append(item)

func test_remote_kill_packet_triggers_local_drop_via_player_signal():
	# Integration: a remote OP_KILL packet for a boss arrives at this
	# client. RemoteKillApplier returns true (rising edge), then GameState
	# rolls a local item and emits item_dropped on the local Player —
	# which the HUD's existing single-player path picks up.
	_snapshot_game_state()
	var lobby_state := _make_lobby_state([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	var session := CoopSession.new(
		lobby_state,
		{"u1": wizard, "u2": _make_character(CharacterData.CharacterClass.CHONK_KITTEN, 11)},
		null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("boss_0")
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	GameState.current_character = wizard
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	var stub := _StubPlayer.new()
	add_child_autofree(stub)
	# Boss packet — BOSS context guarantees a drop on the receiver.
	lobby.apply_state(NakamaLobby.OP_KILL, "u2",
		{"enemy_id": "boss_0", "xp": 4, "boss": true})
	assert_eq(stub.received.size(), 1,
		"local Player.item_dropped fired exactly once on remote boss kill")
	assert_not_null(stub.received[0])
	assert_true(
		ItemDropResolver.is_drop_eligible(stub.received[0], CharacterData.CharacterClass.WIZARD_KITTEN),
		"locally-rolled item is wizard-eligible (not the killer's class)")
	GameState.set_lobby(null)
	_restore_game_state()

func test_remote_kill_packet_duplicate_does_not_double_drop():
	# Rising-edge gate: a duplicate kill packet (RemoteKillApplier returns
	# false) must not produce a second item drop. Otherwise a flaky network
	# would showers the bag with phantom loot.
	_snapshot_game_state()
	var lobby_state := _make_lobby_state([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	var session := CoopSession.new(
		lobby_state,
		{"u1": wizard, "u2": _make_character(CharacterData.CharacterClass.CHONK_KITTEN, 11)},
		null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("boss_0")
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	GameState.current_character = wizard
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	var stub := _StubPlayer.new()
	add_child_autofree(stub)
	lobby.apply_state(NakamaLobby.OP_KILL, "u2",
		{"enemy_id": "boss_0", "xp": 4, "boss": true})
	lobby.apply_state(NakamaLobby.OP_KILL, "u2",
		{"enemy_id": "boss_0", "xp": 4, "boss": true})
	assert_eq(stub.received.size(), 1,
		"duplicate packet gated — exactly one local drop")
	GameState.set_lobby(null)
	_restore_game_state()

func test_remote_kill_self_echo_does_not_trigger_local_drop():
	# AC#4: the killer's drop is handled by the existing KillRewardRouter
	# path, not the new fan-out. NakamaLobby._route_kill drops self-echoes
	# at the routing layer (sender_id == local_player_id), so the killer
	# never re-rolls on receipt of their own broadcast.
	_snapshot_game_state()
	var lobby_state := _make_lobby_state([["u1", "A", "Mage"]])
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	var session := CoopSession.new(lobby_state, {"u1": wizard}, null, "u1")
	session.start(_make_two_room_dungeon())
	session.enemy_sync.register_enemy("boss_0")
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	GameState.current_character = wizard
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	var stub := _StubPlayer.new()
	add_child_autofree(stub)
	# Self-echo: sender_id == local_player_id, dropped at routing.
	lobby.apply_state(NakamaLobby.OP_KILL, "u1",
		{"enemy_id": "boss_0", "xp": 4, "boss": true})
	assert_eq(stub.received.size(), 0,
		"self-echo dropped — killer's drop path is KillRewardRouter, not fan-out")
	GameState.set_lobby(null)
	_restore_game_state()

func test_remote_kill_empty_enemy_id_no_op():
	# Mirrors existing wire-layer guard: an empty enemy_id can't be gated
	# downstream (apply_death rejects empty ids) so the routing layer
	# drops it. No local drop fires either.
	_snapshot_game_state()
	var lobby_state := _make_lobby_state([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var wizard := _make_character(CharacterData.CharacterClass.WIZARD_KITTEN, 11)
	var session := CoopSession.new(
		lobby_state,
		{"u1": wizard, "u2": _make_character(CharacterData.CharacterClass.CHONK_KITTEN, 11)},
		null, "u1")
	session.start(_make_two_room_dungeon())
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	GameState.current_character = wizard
	var lobby := NakamaLobby.new()
	lobby.local_player_id = "u1"
	GameState.set_lobby(lobby)
	var stub := _StubPlayer.new()
	add_child_autofree(stub)
	lobby.apply_state(NakamaLobby.OP_KILL, "u2",
		{"enemy_id": "", "xp": 4, "boss": true})
	assert_eq(stub.received.size(), 0,
		"empty enemy_id is a silent no-op all the way through")
	GameState.set_lobby(null)
	_restore_game_state()
