extends GutTest

# Tests for ChestEntity. Slice 1 (#218) introduced the state machine; slice 4
# (#221) layered per-player open state for co-op. Drives the lifecycle through
# public methods without a SceneTree, mirroring the headless tick() pattern
# from test_healing_box.gd.

var _spawned: Array = []
var _sessions: Array = []

func _make() -> ChestEntity:
	var e := ChestEntity.new()
	_spawned.append(e)
	return e

func after_each() -> void:
	for e in _spawned:
		if is_instance_valid(e):
			e.free()
	_spawned.clear()
	# Tear down sessions so per-run managers release their references.
	for s in _sessions:
		if s != null:
			s.end()
	_sessions.clear()


func _make_character() -> CharacterData:
	return CharacterFactory.create_default("Mage")


func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


# Builds a CoopSession with the given player_ids so ChestEntity can query
# session.player_ids in _all_present_players_have_opened. Mirrors the
# _make_session_with_lobby helper in test_room_spawn_planner.gd:27-48 but
# parametrized on the player count.
func _make_session(player_ids: Array) -> CoopSession:
	var lobby := LobbyState.new()
	lobby.room_code = "ABCDE"
	var characters: Dictionary = {}
	for i in range(player_ids.size()):
		var pid: String = player_ids[i]
		var lp := LobbyPlayer.make(pid, "Kitten%d" % i, "Mage", i == 0)
		lobby.add_player(lp)
		characters[pid] = CharacterFactory.create_default("Mage")
	var s := CoopSession.new(lobby, characters)
	# Tiny dungeon so start() succeeds — the chest tests only consume
	# session.player_ids, but constructing without start() leaves the
	# session inactive which exercises a different code path.
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	start.connections = [1]
	d.add_room(start)
	d.add_room(boss)
	d.start_id = 0
	d.boss_id = 1
	s.start(d)
	_sessions.append(s)
	return s


# --- slice 1 (#218) lifecycle — preserved under new open(player_id, ...) ---

func test_open_transitions_to_lingering_and_credits_ledger():
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	var ok := entity.open("p1", _make_character(), _seeded_rng(1))
	assert_true(ok, "open() returns true on first call")
	assert_eq(entity.ledger.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD)
	assert_eq(entity.state, ChestEntity.State.OPENED_LINGERING,
		"no session wired → behaves like solo, fade starts on first open")
	var path := entity.current_sprite_texture_path()
	assert_true(path.ends_with("chest_open_sprite.png"),
		"sprite swapped to open texture, got %s" % path)


func test_state_machine_linger_then_fade_then_freed():
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	entity.open("p1", _make_character(), _seeded_rng(1))

	entity.tick(ChestEntity.LINGER_SECONDS)
	assert_eq(entity.state, ChestEntity.State.FADING)
	assert_almost_eq(entity.modulate.a, 1.0, 0.001)

	entity.tick(ChestEntity.FADE_SECONDS / 2.0)
	assert_eq(entity.state, ChestEntity.State.FADING)
	assert_almost_eq(entity.modulate.a, 0.5, 0.05)

	entity.tick(ChestEntity.FADE_SECONDS / 2.0 + 0.01)
	assert_eq(entity.state, ChestEntity.State.FREED)
	assert_true(entity.freed, "entity marks itself freed for tests")


func test_interact_only_offered_while_closed():
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	assert_true(entity.should_offer_interact(), "CLOSED offers interact")
	entity.open("p1", _make_character(), _seeded_rng(1))
	assert_false(entity.should_offer_interact(), "OPENED_LINGERING blocks interact")
	entity.tick(ChestEntity.LINGER_SECONDS)
	assert_eq(entity.state, ChestEntity.State.FADING)
	assert_false(entity.should_offer_interact(), "FADING blocks interact")


func test_opened_signal_emits_once_with_drop_payload():
	# RARE has 50% drop chance — find a seed that produces a non-null drop
	# so the payload assertion is deterministic (mirrors the seed-discovery
	# pattern in test_chest_loot_currency.gd:138-146).
	var character := _make_character()
	for s in range(1, 50):
		var probe := Chest.make(Chest.Kind.RARE)
		probe.open(CurrencyLedger.new(), character, _seeded_rng(s))
		if probe.last_item_drop != null:
			var entity := _make()
			entity.chest = Chest.make(Chest.Kind.RARE)
			entity.ledger = CurrencyLedger.new()
			watch_signals(entity)
			entity.open("p1", character, _seeded_rng(s))
			assert_signal_emit_count(entity, "opened_by", 1)
			var params = get_signal_parameters(entity, "opened_by", 0)
			assert_not_null(params, "opened_by signal recorded parameters")
			assert_eq(params[0], "p1", "opened_by payload includes player_id")
			assert_true(params[1] is ItemData, "opened_by payload includes ItemData drop")
			return
	fail_test("no seed in 1..50 produced a rare item drop")


# --- slice 4 (#221) co-op per-player open state ---

func test_solo_open_fades_immediately_like_before():
	# Regression guard for #218 behavior under a 1-player session.
	var session := _make_session(["p1"])
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	entity.session = session
	entity.open("p1", _make_character(), _seeded_rng(1))
	assert_eq(entity.state, ChestEntity.State.OPENED_LINGERING,
		"1-player session: first open immediately starts the fade")


func test_coop_first_open_does_not_start_fade():
	var session := _make_session(["p1", "p2"])
	var l1 := CurrencyLedger.new()
	var l2 := CurrencyLedger.new()
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledgers = {"p1": l1, "p2": l2}
	entity.session = session
	watch_signals(entity)
	var ok := entity.open("p1", _make_character(), _seeded_rng(1))
	assert_true(ok, "p1's first open succeeds")
	assert_eq(entity.state, ChestEntity.State.CLOSED,
		"chest stays CLOSED until both players have opened")
	assert_eq(l1.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD,
		"p1's ledger credited")
	assert_eq(l2.balance(CurrencyLedger.Currency.GOLD), 0,
		"p2's ledger untouched")
	assert_signal_emit_count(entity, "opened_by", 1)
	var params = get_signal_parameters(entity, "opened_by", 0)
	assert_eq(params[0], "p1", "opened_by payload identifies p1")


func test_coop_second_open_triggers_linger():
	var session := _make_session(["p1", "p2"])
	var l1 := CurrencyLedger.new()
	var l2 := CurrencyLedger.new()
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledgers = {"p1": l1, "p2": l2}
	entity.session = session
	watch_signals(entity)
	entity.open("p1", _make_character(), _seeded_rng(1))
	entity.open("p2", _make_character(), _seeded_rng(2))
	assert_eq(entity.state, ChestEntity.State.OPENED_LINGERING,
		"chest starts fade once every present player has opened")
	assert_eq(l1.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD)
	assert_eq(l2.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD,
		"p2's ledger credited independently of p1's")
	assert_signal_emit_count(entity, "opened_by", 2)


func test_same_player_cannot_open_twice():
	var session := _make_session(["p1", "p2"])
	var l1 := CurrencyLedger.new()
	var l2 := CurrencyLedger.new()
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledgers = {"p1": l1, "p2": l2}
	entity.session = session
	entity.open("p1", _make_character(), _seeded_rng(1))
	var balance_after := l1.balance(CurrencyLedger.Currency.GOLD)
	var ok2 := entity.open("p1", _make_character(), _seeded_rng(2))
	assert_false(ok2, "p1's second open is a no-op")
	assert_eq(l1.balance(CurrencyLedger.Currency.GOLD), balance_after,
		"p1's ledger unchanged on the no-op second open")
	assert_eq(entity.state, ChestEntity.State.CLOSED,
		"chest still CLOSED because p2 has not opened yet")


func test_should_offer_interact_false_for_player_who_already_opened():
	var session := _make_session(["p1", "p2"])
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledgers = {"p1": CurrencyLedger.new(), "p2": CurrencyLedger.new()}
	entity.session = session
	entity.open("p1", _make_character(), _seeded_rng(1))
	assert_false(entity.should_offer_interact("p1"),
		"p1 already opened → no prompt for p1")
	assert_true(entity.should_offer_interact("p2"),
		"p2 has not opened yet → prompt still shows for p2")


func test_second_open_is_a_noop():
	# Solo-path idempotence regression (#218): without a session, second
	# open returns false because state has already advanced past CLOSED.
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	watch_signals(entity)
	entity.open("p1", _make_character(), _seeded_rng(1))
	var balance_after_first := entity.ledger.balance(CurrencyLedger.Currency.GOLD)
	var ok2 := entity.open("p1", _make_character(), _seeded_rng(2))
	assert_false(ok2)
	assert_eq(entity.ledger.balance(CurrencyLedger.Currency.GOLD), balance_after_first)
	assert_eq(entity.state, ChestEntity.State.OPENED_LINGERING)
	assert_signal_emit_count(entity, "opened_by", 1, "opened_by only fires once")
