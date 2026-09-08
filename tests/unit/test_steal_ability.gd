extends GutTest

# Steal archetype (PRD #518 / issue #572). Completes Trash Panda Tyrone: grabs
# the player's gold on commit, then flees with it — the player's counter is
# priority (chase him down before he escapes) and the theft is only reversed
# by killing him. Same _MockEnemy/_MockPlayer shape as test_enemy_behavior.gd
# and test_zone_denial_ability.gd, with the mock player extended to carry a
# gold balance and the take_gold()/gold_balance() duck-typed interface the
# real Player exposes (see StealAbility for the authority note).

class _MockData:
	var enemy_id: String = ""

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var data: _MockData = _MockData.new()
	var _player_ref = null

# Extends the plain _MockPlayer shape with a gold balance and the same
# gold_balance()/take_gold() interface Player.gd exposes, so StealAbility can
# treat the mock and the real node identically — it never touches a balance
# field directly (see StealAbility's authority note).
class _MockPlayer extends Node2D:
	var gold: int = 0

	func gold_balance() -> int:
		return gold

	func take_gold(amount: int) -> int:
		var take: int = mini(amount, gold)
		if take <= 0:
			return 0
		gold -= take
		return take


func _make(steal_amount: int = 10) -> StealAbility:
	return StealAbility.new(1.0, 0.1, 0.2, 0.1, 40.0, steal_amount)


func _drive_to_begin(b: StealAbility, e: _MockEnemy) -> bool:
	for _i in range(int(ceil(b.cooldown() / 1.0)) + 1):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
			return true
	return false


func _drive_into_commit(b: StealAbility, e: _MockEnemy) -> void:
	var step := 0.02
	var elapsed := 0.0
	while elapsed < b.windup_duration() + 0.02:
		b.tick(step, e)
		elapsed += step


# --- 1. Core wiring -----------------------------------------------------------

func test_steal_removes_gold_from_player_on_commit_frame():
	var b := _make(10)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.gold = 50
	e._player_ref = p
	assert_true(_drive_to_begin(b, e), "the ability should have begun a firing")
	_drive_into_commit(b, e)
	assert_eq(p.gold, 40, "the player's gold should have decreased by the steal amount")


# --- 2. Fire-once ---------------------------------------------------------------

func test_gold_decreases_exactly_once_per_firing():
	var b := _make(10)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.gold = 50
	e._player_ref = p
	_drive_to_begin(b, e)
	_drive_into_commit(b, e)
	assert_eq(p.gold, 40, "gold should have decreased once by now")
	for _i in range(10):
		b.tick(0.02, e)
	assert_eq(p.gold, 40, "further commit-window frames must not steal a second time")


# --- 3. Never negative ------------------------------------------------------------

func test_steal_never_takes_more_than_the_player_has():
	var b := _make(10)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.gold = 4
	e._player_ref = p
	_drive_to_begin(b, e)
	_drive_into_commit(b, e)
	assert_eq(p.gold, 0, "a player holding less than the steal amount should lose all of it and land at zero")


# --- 4. Zero gold ----------------------------------------------------------------

func test_zero_gold_player_loses_nothing_and_ability_does_not_fire():
	var b := _make(10)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.gold = 0
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown() / 1.0)) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_eq(p.gold, 0, "a zero-gold player must lose nothing")
	assert_null(b.active_zone, "the ability must decline to fire against a zero-gold player")


# --- 5. Outside the zone -----------------------------------------------------------

func test_player_outside_the_zone_at_commit_loses_nothing():
	var b := _make(10)
	var e := _MockEnemy.new()
	e.global_position = Vector2.ZERO
	var p := _MockPlayer.new()
	p.gold = 50
	p.global_position = Vector2(1000.0, 0.0)  # well outside the grab radius
	e._player_ref = p
	_drive_to_begin(b, e)
	_drive_into_commit(b, e)
	assert_eq(p.gold, 50, "zone-is-hitbox: a player outside the drawn zone at commit must lose nothing")


# --- 6. Flight ---------------------------------------------------------------------

func test_successful_steal_makes_tyrone_flee_away_from_the_player():
	var b := _make(10)
	var e := _MockEnemy.new()
	e.global_position = Vector2.ZERO
	var p := _MockPlayer.new()
	p.gold = 50
	e._player_ref = p
	_drive_to_begin(b, e)
	_drive_into_commit(b, e)
	assert_true(b.is_fleeing(), "a successful steal should flip the ability into fleeing")
	var dir := b.desired_direction(Vector2.ZERO, Vector2(100.0, 0.0))
	assert_eq(dir, Vector2(-1.0, 0.0), "fleeing should point away from the player")


# --- 7. Recovery ---------------------------------------------------------------------

func test_stolen_amount_is_readable_and_matches_what_was_taken():
	var b := _make(10)
	var e := _MockEnemy.new()
	var p := _MockPlayer.new()
	p.gold = 50
	e._player_ref = p
	_drive_to_begin(b, e)
	_drive_into_commit(b, e)
	assert_eq(b.stolen_amount, 10, "the carried amount should equal what was actually taken")


# --- 8. Edge cases ---------------------------------------------------------------------

func test_null_player_does_not_fire():
	var b := _make(10)
	var e := _MockEnemy.new()
	e._player_ref = null
	for _i in range(int(ceil(b.cooldown() / 1.0)) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.active_zone, "a null player reference must never let the ability fire")


func test_player_exactly_at_enemy_position_still_steals():
	var b := _make(10)
	var e := _MockEnemy.new()
	e.global_position = Vector2.ZERO
	var p := _MockPlayer.new()
	p.gold = 50
	p.global_position = Vector2.ZERO
	e._player_ref = p
	_drive_to_begin(b, e)
	_drive_into_commit(b, e)
	assert_eq(p.gold, 40, "a coincident player must not crash and should still be caught by the zone")


func test_idle_enemy_publishes_nothing():
	var b := _make(10)
	var e := _MockEnemy.new()
	e.state = 0  # IDLE
	var p := _MockPlayer.new()
	p.gold = 50
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown() / 1.0)) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.active_zone, "an IDLE enemy must not publish a steal zone")


func test_dead_enemy_publishes_nothing():
	var b := _make(10)
	var e := _MockEnemy.new()
	e.state = 3  # DEAD
	var p := _MockPlayer.new()
	p.gold = 50
	e._player_ref = p
	for _i in range(int(ceil(b.cooldown() / 1.0)) + 5):
		b.tick(1.0, e)
		if b.wants_to_fire():
			b.begin(e)
	assert_null(b.active_zone, "a DEAD enemy must not publish a steal zone")
