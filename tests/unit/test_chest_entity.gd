extends GutTest

# Tests for ChestEntity (PRD #217, slice 1 / issue #218). Drives the open
# + lifecycle path through public methods without a SceneTree, mirroring
# the headless tick() pattern from test_healing_box.gd.

var _spawned: Array = []

func _make() -> ChestEntity:
	var e := ChestEntity.new()
	_spawned.append(e)
	return e

func after_each() -> void:
	for e in _spawned:
		if is_instance_valid(e):
			e.free()
	_spawned.clear()


func _make_character() -> CharacterData:
	return CharacterFactory.create_default("Mage")


func _seeded_rng(seed_val: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


func test_open_transitions_to_lingering_and_credits_ledger():
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	var ok := entity.open(_make_character(), _seeded_rng(1))
	assert_true(ok, "open() returns true on first call")
	assert_eq(entity.ledger.balance(CurrencyLedger.Currency.GOLD), Chest.STANDARD_GOLD)
	assert_eq(entity.state, ChestEntity.State.OPENED_LINGERING)
	var path := entity.current_sprite_texture_path()
	assert_true(path.ends_with("chest_open_sprite.png"),
		"sprite swapped to open texture, got %s" % path)


func test_state_machine_linger_then_fade_then_freed():
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	entity.open(_make_character(), _seeded_rng(1))

	entity.tick(ChestEntity.LINGER_SECONDS)
	assert_eq(entity.state, ChestEntity.State.FADING)
	assert_almost_eq(entity.modulate.a, 1.0, 0.001)

	entity.tick(ChestEntity.FADE_SECONDS / 2.0)
	assert_eq(entity.state, ChestEntity.State.FADING)
	assert_almost_eq(entity.modulate.a, 0.5, 0.05)

	entity.tick(ChestEntity.FADE_SECONDS / 2.0 + 0.01)
	assert_eq(entity.state, ChestEntity.State.FREED)
	assert_true(entity.freed, "entity marks itself freed for tests")


func test_second_open_is_a_noop():
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	watch_signals(entity)
	entity.open(_make_character(), _seeded_rng(1))
	var balance_after_first := entity.ledger.balance(CurrencyLedger.Currency.GOLD)
	var ok2 := entity.open(_make_character(), _seeded_rng(2))
	assert_false(ok2)
	assert_eq(entity.ledger.balance(CurrencyLedger.Currency.GOLD), balance_after_first)
	assert_eq(entity.state, ChestEntity.State.OPENED_LINGERING)
	assert_signal_emit_count(entity, "opened", 1, "opened only fires once")


func test_interact_only_offered_while_closed():
	var entity := _make()
	entity.chest = Chest.make(Chest.Kind.STANDARD)
	entity.ledger = CurrencyLedger.new()
	assert_true(entity.should_offer_interact(), "CLOSED offers interact")
	entity.open(_make_character(), _seeded_rng(1))
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
			entity.open(character, _seeded_rng(s))
			assert_signal_emit_count(entity, "opened", 1)
			var params = get_signal_parameters(entity, "opened", 0)
			assert_not_null(params, "opened signal recorded parameters")
			assert_true(params[0] is ItemData, "opened payload is ItemData")
			return
	fail_test("no seed in 1..50 produced a rare item drop")
