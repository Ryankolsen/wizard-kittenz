extends GutTest

# Tests for PRD #53 / issue #65 — Gold sources from combat. Two ways
# Gold enters the local CurrencyLedger during a dungeon run:
#   1. EnemyData.gold_reward on every enemy kill (via KillRewardRouter).
#   2. ROOM_CLEAR_GOLD bonus on the last expected death (via RoomClearWatcher).
# Both pay the full amount (no party-split — Gold is per-character).

# --- helpers --------------------------------------------------------------

func _make_character() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.MAGE)

func _make_standard_room(room_id: int, kind: int = EnemyData.EnemyKind.SLIME) -> Room:
	var r := Room.make(room_id, Room.TYPE_STANDARD)
	r.enemy_kind = kind
	return r

func _make_dungeon_with(room: Room) -> Dungeon:
	var d := Dungeon.new()
	var s := Room.make(0, Room.TYPE_START)
	s.connections = [room.id]
	d.add_room(s)
	d.add_room(room)
	d.start_id = s.id
	d.boss_id = -1
	return d

func _make_controller_for(room: Room) -> DungeonRunController:
	var d := _make_dungeon_with(room)
	var c := DungeonRunController.new()
	c.start(d)
	return c

# --- EnemyData.gold_reward defaults --------------------------------------

func test_make_new_slime_sets_non_zero_gold_reward():
	var e := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	assert_true(e.gold_reward > 0)
	assert_eq(e.gold_reward, 2)

func test_make_new_bat_sets_gold_reward():
	var e := EnemyData.make_new(EnemyData.EnemyKind.BAT)
	assert_eq(e.gold_reward, 2)

func test_make_new_rat_sets_gold_reward():
	var e := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	assert_eq(e.gold_reward, 3)

# --- KillRewardRouter credits gold to the ledger -------------------------

func test_route_kill_solo_credits_gold_to_ledger():
	var c := _make_character()
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	var ledger := CurrencyLedger.new()
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), enemy.gold_reward)

func test_route_kill_null_ledger_safe():
	var c := _make_character()
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, null)
	pass_test("no crash with null ledger")

func test_route_kill_accumulates_gold_across_kills():
	var c := _make_character()
	var ledger := CurrencyLedger.new()
	KillRewardRouter.route_kill(c, EnemyData.make_new(EnemyData.EnemyKind.SLIME), null, "", null, null, ledger)
	KillRewardRouter.route_kill(c, EnemyData.make_new(EnemyData.EnemyKind.RAT), null, "", null, null, ledger)
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 5, "2 (slime) + 3 (rat)")

# --- RoomClearWatcher credits ROOM_CLEAR_GOLD bonus ----------------------

func test_room_clear_bonus_credits_gold():
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var ledger := CurrencyLedger.new()
	var w := RoomClearWatcher.new()
	assert_true(w.watch(room, controller, null, null, ledger))
	# Drive notify_death with the spawn-planner's expected id so the
	# watcher's per-room expected set recognizes it.
	var ids := RoomSpawnPlanner.enemy_ids_for_room(room)
	assert_eq(ids.size(), 1)
	assert_true(w.notify_death(ids[0]))
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), RoomClearWatcher.ROOM_CLEAR_GOLD)

func test_room_clear_double_notify_does_not_double_credit_gold():
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var ledger := CurrencyLedger.new()
	var w := RoomClearWatcher.new()
	w.watch(room, controller, null, null, ledger)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(room)
	w.notify_death(ids[0])
	w.notify_death(ids[0])
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), RoomClearWatcher.ROOM_CLEAR_GOLD,
		"idempotent — second notify is a no-op for both clear edge and Gold credit")

func test_room_clear_auto_clear_pays_no_gold():
	# Power-up rooms have no enemies — watch() auto-clears immediately
	# but should NOT pay the Gold bonus (combat-only rule, mirrors XP).
	var room := Room.make(5, Room.TYPE_POWERUP)
	room.power_up_type = "catnip"
	var controller := _make_controller_for(_make_standard_room(99))
	var ledger := CurrencyLedger.new()
	var w := RoomClearWatcher.new()
	w.watch(room, controller, null, null, ledger)
	assert_true(w.is_cleared(), "no-enemy room auto-clears")
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), 0,
		"auto-clear rooms (start, power-up) do not pay Gold")

func test_room_clear_null_ledger_safe():
	var room := _make_standard_room(3)
	var controller := _make_controller_for(room)
	var w := RoomClearWatcher.new()
	w.watch(room, controller, null, null, null)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(room)
	assert_true(w.notify_death(ids[0]))
	pass_test("no crash with null ledger")

# --- Full combat flow: kill credit + room clear bonus stack --------------

func test_kill_plus_room_clear_credits_both_amounts():
	var room := _make_standard_room(3, EnemyData.EnemyKind.SLIME)
	var controller := _make_controller_for(room)
	var ledger := CurrencyLedger.new()
	var w := RoomClearWatcher.new()
	w.watch(room, controller, null, null, ledger)
	var ids := RoomSpawnPlanner.enemy_ids_for_room(room)
	# Simulate the kill side first (KillRewardRouter), then the room-clear edge.
	var c := _make_character()
	var enemy := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	KillRewardRouter.route_kill(c, enemy, null, "", null, null, ledger)
	w.notify_death(ids[0])
	assert_eq(ledger.balance(CurrencyLedger.Currency.GOLD), enemy.gold_reward + RoomClearWatcher.ROOM_CLEAR_GOLD)
