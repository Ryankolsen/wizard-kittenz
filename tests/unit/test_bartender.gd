extends GutTest

# Tests for the bartender NPC. Reworked in #197 — the bartender no longer
# emits shop_requested directly on attack; pressing attack while in range
# opens a SpeechBubble with [Shop, Exit] options, and shop_requested fires
# only when the player confirms the Shop row.
#
# Tests instantiate the scene directly so the proximity + attack +
# bubble-mount + option-dispatch wiring is exercised without spinning up a
# player, shop overlay, or full bar room.

const BARTENDER_SCENE_PATH := "res://scenes/bartender.tscn"


func _make_bartender() -> Bartender:
	var npc: Bartender = load(BARTENDER_SCENE_PATH).instantiate()
	add_child_autofree(npc)
	return npc


# --- #197: bubble-menu flow ------------------------------------------------

func test_bartender_opens_bubble_on_attack_in_range():
	# Core wiring: enter range, press attack, bartender now has a SpeechBubble
	# child mounted. Replaces the old "emits shop_requested directly" test.
	var bartender := _make_bartender()
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	assert_not_null(bubble, "attack press mounts a SpeechBubble")
	assert_true(bubble is SpeechBubble, "mounted child is a SpeechBubble")


func test_bartender_options_include_get_a_beer():
	# Content: bubble menu rows are exactly [Shop, Get a beer, Exit] in that
	# order — Beer wedged between Shop and Exit so the existing nav muscle
	# memory (down-once → Exit) only changes when Beer is affordable.
	var bartender := _make_bartender()
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	var list: NPCOptionList = bubble._list
	assert_eq(list.size(), 3, "bartender menu has 3 options")
	assert_eq(list.get(0).label, "Shop")
	assert_eq(list.get(1).label, "Get a beer")
	assert_eq(list.get(2).label, "Exit")


func test_selecting_shop_emits_shop_requested():
	# Picking the Shop row dispatches "open_shop", which the bartender's
	# _handle_effect routes to shop_requested.emit(). The default cursor
	# already lands on row 0 (Shop), so confirm() without nav lands on Shop.
	var bartender := _make_bartender()
	var emits := [0]
	bartender.shop_requested.connect(func(): emits[0] += 1)
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	bubble.confirm()
	assert_eq(emits[0], 1, "shop_requested emits exactly once for Shop confirm")


func test_selecting_exit_closes_bubble_without_shop():
	# Picking Exit dismisses the bubble and does NOT emit shop_requested.
	var bartender := _make_bartender()
	var emits := [0]
	bartender.shop_requested.connect(func(): emits[0] += 1)
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	bubble.move_next()  # Shop (0) -> Exit (1)
	bubble.confirm()
	assert_eq(emits[0], 0, "Exit does not emit shop_requested")
	assert_null(bartender.get_bubble(),
		"bubble cleared from bartender after Exit confirm")


func test_repeated_attack_presses_after_exit_reopen_bubble():
	# Re-arming: after Exit closes the bubble, pressing attack again opens
	# a fresh bubble. Locks in that the bubble lifecycle is per-interaction,
	# not "first press only".
	var bartender := _make_bartender()
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var first := bartender.get_bubble()
	first.move_next()
	first.confirm()  # Exit
	assert_null(bartender.get_bubble(), "bubble cleared after Exit")
	bartender._on_attack_pressed()
	var second := bartender.get_bubble()
	assert_not_null(second, "second attack press opens a fresh bubble")
	assert_ne(first, second, "fresh bubble instance, not the dismissed one")


func test_bubble_not_mounted_when_player_out_of_range():
	# Gating: pressing attack with no prior _on_player_entered_range does NOT
	# mount a bubble. Player.gd's own attack handler still fires normally.
	var bartender := _make_bartender()
	# Do NOT call _on_player_entered_range — player has never been in range.
	bartender._on_attack_pressed()
	assert_null(bartender.get_bubble(),
		"no bubble mounted when player is out of range")


func test_bubble_closes_when_player_leaves_range():
	# Proximity exit auto-dismisses the bubble (AC: "Walking out of proximity
	# closes the bubble automatically").
	var bartender := _make_bartender()
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	assert_not_null(bartender.get_bubble(), "bubble open while in range")
	bartender._on_player_exited_range()
	assert_null(bartender.get_bubble(),
		"bubble cleared when player walks out of range")


# --- #199: Get a beer option ----------------------------------------------

func _make_bartender_with_economy(gold: int) -> Array:
	# Returns [bartender, ledger, character] with a bartender wired to a
	# fresh ledger + character — no GameState autoload required.
	var bartender := _make_bartender()
	var ledger := CurrencyLedger.new()
	if gold > 0:
		ledger.credit(gold, CurrencyLedger.Currency.GOLD)
	var character := CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	bartender.setup_economy(ledger, character)
	return [bartender, ledger, character]


func test_buying_beer_deducts_gold_and_applies_buff():
	var trio := _make_bartender_with_economy(100)
	var bartender: Bartender = trio[0]
	var ledger: CurrencyLedger = trio[1]
	var character: CharacterData = trio[2]
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	bubble.move_next()  # Shop (0) -> Beer (1)
	bubble.confirm()
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 75,
		"Beer costs exactly 25 gold")
	assert_almost_eq(character.get_damage_multiplier(), 1.2, 0.001,
		"Beer applies a +20% damage multiplier")


func test_beer_option_disabled_when_gold_below_25():
	var trio := _make_bartender_with_economy(10)
	var bartender: Bartender = trio[0]
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	var list: NPCOptionList = bubble._list
	assert_false(list.get(1).is_enabled(),
		"Beer option is disabled when gold < 25")
	# Initial cursor is on Shop (0). One move_next should skip Beer (1)
	# and land on Exit (2).
	bubble.move_next()
	assert_eq(bubble.selection.current_index(), 2,
		"Navigation skips disabled Beer row, lands on Exit")


func test_confirming_disabled_beer_does_not_charge_or_buff():
	# Belt-and-suspenders: even if the cursor were forced onto a disabled
	# Beer row, confirming it must not debit or buff.
	var trio := _make_bartender_with_economy(10)
	var bartender: Bartender = trio[0]
	var ledger: CurrencyLedger = trio[1]
	var character: CharacterData = trio[2]
	# Dispatch the effect directly to bypass the controller's disable-skip.
	bartender._handle_effect("buy_beer")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 10,
		"Gold unchanged when beer is unaffordable")
	assert_almost_eq(character.get_damage_multiplier(), 1.0, 0.001,
		"No buff applied when beer is unaffordable")


func test_beer_enabled_state_reevaluated_after_shop_close():
	# Affordability snapshots at open time would leave a stale "enabled"
	# answer after the player spends in the shop. Reopen → predicate runs
	# again → row reflects current balance.
	var trio := _make_bartender_with_economy(30)
	var bartender: Bartender = trio[0]
	var ledger: CurrencyLedger = trio[1]
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	assert_true(bubble._list.get(1).is_enabled(),
		"Beer enabled at 30 gold on first open")
	# Simulate the player picking Shop → spending → shop closing.
	bartender._handle_effect("open_shop")
	ledger.debit(25, CurrencyLedger.Currency.GOLD)  # leaves 5 gold
	bartender.open_menu()  # what BarRoom._on_shop_closed calls
	var reopened := bartender.get_bubble()
	assert_not_null(reopened, "menu reopens after shop close")
	assert_false(reopened._list.get(1).is_enabled(),
		"Beer now disabled — predicate re-evaluated against current gold")


func test_beer_enabled_at_exactly_25_gold():
	# Predicate is gold >= 25, not gold > 25. Exactly 25 is affordable.
	var trio := _make_bartender_with_economy(25)
	var bartender: Bartender = trio[0]
	bartender._on_player_entered_range()
	bartender._on_attack_pressed()
	var bubble := bartender.get_bubble()
	assert_true(bubble._list.get(1).is_enabled(),
		"Beer enabled at exactly 25 gold")


# --- #191: sprite asset ----------------------------------------------------

func test_bartender_sprite_uses_bartender_png():
	var bartender := _make_bartender()
	var sprite := bartender.find_child("Sprite2D", true, false) as Sprite2D
	assert_not_null(sprite, "bartender has a Sprite2D child")
	assert_not_null(sprite.texture, "bartender sprite has a texture assigned")
	assert_eq(sprite.texture.resource_path,
		"res://assets/sprites/bartender.png",
		"Bartender uses new bartender.png sprite")


# --- #183: bar-room embedding ----------------------------------------------

func test_bartender_lives_in_bar_room():
	var room: BarRoom = load("res://scenes/bar_room.tscn").instantiate()
	add_child_autofree(room)
	var bartender := room.find_child("Bartender", true, false)
	assert_not_null(bartender, "bar room contains a Bartender node")


func test_bartender_positioned_behind_bar_counter():
	# Y-sort relationship: bartender stands behind the counter (smaller y →
	# drawn before the counter so the counter overlaps from the front).
	var room: BarRoom = load("res://scenes/bar_room.tscn").instantiate()
	add_child_autofree(room)
	var bartender := room.find_child("Bartender", true, false) as Node2D
	var counter := room.find_child("BarCounter", true, false) as Node2D
	assert_not_null(bartender, "bartender exists")
	assert_not_null(counter, "counter exists")
	assert_lt(bartender.position.y, counter.position.y,
		"bartender sits behind (smaller y than) the bar counter for y-sort")
