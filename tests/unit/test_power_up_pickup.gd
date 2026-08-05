extends GutTest

# Issue #468: PowerUpPickup's TYPE_ALE pickup path feeds the same shared
# `drinks` counter as the bartender's beer purchase (test_bartender.gd), so
# both sources contribute to one running total for the tiered Happy Hour/
# Bar Regular/Liver of Steel achievements. The pickup reaches GameState the
# same way Player/enemy/chest call sites do (autoload, not injection), so
# these tests swap the real GameState.achievement_service instance rather
# than using Player's _inject_game_state seam.

class FakeGameState:
	var local_player_id: String = "me"
	var coop_session = null
	var lobby = null
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()
	var achievement_service: AchievementService = AchievementService.new(AccountSaveData.new())


func _make_player() -> Player:
	var fake := FakeGameState.new()
	fake.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	p._inject_game_state(fake)
	add_child_autofree(p)
	return p


func _make_pickup(type_id: String) -> PowerUpPickup:
	var pickup := PowerUpPickup.new()
	pickup.power_up_type = type_id
	add_child_autofree(pickup)
	return pickup


func before_each() -> void:
	GameState.achievement_service = AchievementService.new(AccountSaveData.new())


func after_each() -> void:
	GameState.achievement_service = AchievementService.new(AccountSaveData.new())


func test_ale_pickup_increments_drinks_counter():
	var pickup := _make_pickup(PowerUpEffect.TYPE_ALE)
	var p := _make_player()
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 1,
		"picking up an ale power-up must increment the shared drinks counter")


func test_catnip_pickup_does_not_increment_drinks_counter():
	var pickup := _make_pickup(PowerUpEffect.TYPE_CATNIP)
	var p := _make_player()
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 0,
		"a catnip pickup must not touch the drinks counter")


func test_mushroom_pickup_does_not_increment_drinks_counter():
	var pickup := _make_pickup(PowerUpEffect.TYPE_MUSHROOMS)
	var p := _make_player()
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 0,
		"a mushroom pickup must not touch the drinks counter")


func test_catnip_pickup_increments_catnip_snarfed_counter():
	var pickup := _make_pickup(PowerUpEffect.TYPE_CATNIP)
	var p := _make_player()
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("catnip_snarfed", 0)), 1,
		"picking up a catnip power-up must increment the catnip_snarfed counter")


func test_ale_pickup_does_not_increment_catnip_snarfed_counter():
	var pickup := _make_pickup(PowerUpEffect.TYPE_ALE)
	var p := _make_player()
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("catnip_snarfed", 0)), 0,
		"an ale pickup must not touch the catnip_snarfed counter")


func test_mushroom_pickup_does_not_increment_catnip_snarfed_counter():
	var pickup := _make_pickup(PowerUpEffect.TYPE_MUSHROOMS)
	var p := _make_player()
	pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("catnip_snarfed", 0)), 0,
		"a mushroom pickup must not touch the catnip_snarfed counter")


func test_ale_and_beer_share_the_same_counter():
	# Buy 2 beers, then pick up 3 ale power-ups: combined total is 5, which
	# unlocks Happy Hour.
	var ledger := CurrencyLedger.new()
	ledger.credit(100, CurrencyLedger.Currency.GOLD)
	var character := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var bartender: Bartender = load("res://scenes/bartender.tscn").instantiate()
	add_child_autofree(bartender)
	bartender.setup_economy(ledger, character)
	bartender._handle_effect("buy_beer")
	bartender._handle_effect("buy_beer")
	var p := _make_player()
	for i in range(3):
		var pickup := _make_pickup(PowerUpEffect.TYPE_ALE)
		pickup._on_body_entered(p)
	assert_eq(int(GameState.achievement_service.account.achievement_counters.get("drinks", 0)), 5,
		"2 beers + 3 ale pickups must combine to a 5-drink total")
	assert_true(GameState.achievement_service.account.achievement_state.has("happy_hour"),
		"combined 5-drink total unlocks Happy Hour")
