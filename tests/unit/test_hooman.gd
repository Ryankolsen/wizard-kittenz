extends GutTest

# Tests for the Hooman node's follow movement, state-machine wiring, and
# spawn/lifecycle (PRD #491, issue #496).

const MAIN_SCENE_PATH := "res://scenes/main.tscn"


func before_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.coop_session = null
		gs.dungeon_run_controller = null
		gs.local_player_id = ""
		gs.hooman_rental_service = HoomanRentalService.new()
		gs.hooman_spawned = false


func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.coop_session = null
		gs.dungeon_run_controller = null
		gs.hooman_rental_service = HoomanRentalService.new()
		gs.hooman_spawned = false


# --- Core wiring -------------------------------------------------------

func test_tick_forces_follow_when_inactive():
	var h := Hooman.new()
	h.tick(0.016, Vector2.ZERO, 5.0, 0.1, false)
	assert_eq(h.state, HoomanAIState.State.FOLLOW,
		"is_active == false forces FOLLOW even with a near mob and low player HP")
	h.free()


# --- Content details -----------------------------------------------------

func test_follow_velocity_moves_toward_player_beyond_comfort_radius():
	var h := Hooman.new()
	h.global_position = Vector2(Hooman.COMFORT_RADIUS + 100.0, 0.0)
	var player_pos := Vector2.ZERO
	var vel := Hooman.follow_velocity(h.global_position, player_pos)
	assert_lt(vel.x, 0.0, "hooman is to the right of the player, velocity should point left (toward the player)")
	assert_almost_eq(vel.length(), Hooman.FOLLOW_SPEED, 0.01)
	h.free()


func test_follow_snaps_when_beyond_leash_distance():
	var h := Hooman.new()
	var player_pos := Vector2.ZERO
	h.global_position = Vector2(Hooman.LEASH_DISTANCE + 500.0, 0.0)
	h.tick(0.016, player_pos, INF, 1.0, true)
	var dist := h.global_position.distance_to(player_pos)
	assert_lte(dist, Hooman.COMFORT_RADIUS + 0.01,
		"beyond leash distance snaps the hooman to just outside the comfort radius, not a small step closer")
	h.free()


# --- Edge cases: spawn / despawn wiring on main.tscn ----------------------

func test_renting_twice_in_one_run_does_not_spawn_second_node():
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	inst._on_hooman_rented()
	inst._on_hooman_rented()

	assert_eq(get_tree().get_nodes_in_group("hooman").size(), 1,
		"a second rental (later floor) re-activates the service, it does not spawn a second node")


func test_hooman_removed_on_player_death():
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	inst._on_hooman_rented()
	assert_eq(get_tree().get_nodes_in_group("hooman").size(), 1)

	inst.on_player_died()
	await get_tree().process_frame

	assert_eq(get_tree().get_nodes_in_group("hooman").size(), 0,
		"hooman node is freed on the player-death path")


func test_hooman_persists_across_floor_transition_but_goes_idle():
	var gs := get_node_or_null("/root/GameState")
	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame

	inst._on_hooman_rented()
	gs.currency_ledger.credit(HoomanRentalService.RENT_COST_GOLD, CurrencyLedger.Currency.GOLD)
	assert_true(gs.hooman_rental_service.activate(1, gs.currency_ledger))
	assert_true(gs.hooman_rental_service.is_active_for_floor(1))

	# Floor transition bumps dungeons_completed (the floor-number source for
	# both Bartender._floor_number and _tick_hooman) without a real scene
	# reload — the round trip is exercised at the level main_scene reads it
	# from, matching test_main_scene_coop_activation's _finalize_completed_run
	# pattern for avoiding a GUT-runner-clobbering reload_current_scene call.
	gs.meta_tracker.dungeons_completed += 1
	var new_floor: int = gs.meta_tracker.dungeons_completed + 1

	assert_eq(get_tree().get_nodes_in_group("hooman").size(), 1,
		"hooman node is not despawned across a floor transition")
	assert_false(gs.hooman_rental_service.is_active_for_floor(new_floor),
		"rental does not carry over to the new floor")

	inst._hooman.tick(0.016, inst._player.global_position, 5.0, 0.1, false)
	assert_eq(inst._hooman.state, HoomanAIState.State.FOLLOW,
		"idle-until-renewed gate forces FOLLOW on the new floor")


# --- HP pool (issue #497) -------------------------------------------------

func test_take_damage_reduces_hp_and_returns_amount_dealt():
	var h := Hooman.new()
	h.hp = 10
	h.max_hp = 10
	h.defense = 0
	assert_eq(h.take_damage(4), 4)
	assert_eq(h.hp, 6)
	h.free()


func test_take_damage_does_not_go_below_zero():
	var h := Hooman.new()
	h.hp = 3
	h.max_hp = 10
	assert_eq(h.take_damage(10), 3, "amount actually dealt is capped at remaining hp")
	assert_eq(h.hp, 0)
	h.free()


func test_hp_reaching_zero_triggers_defeat_and_clears_rental() -> void:
	var service := HoomanRentalService.new()
	var ledger := CurrencyLedger.new()
	ledger.credit(HoomanRentalService.RENT_COST_GOLD, CurrencyLedger.Currency.GOLD)
	assert_true(service.activate(2, ledger))
	assert_true(service.is_active_for_floor(2))

	var h := Hooman.new()
	h.hp = 5
	h.max_hp = 5
	h.rental_service = service

	watch_signals(h)
	h.take_damage(10)

	assert_signal_emitted(h, "defeated")
	assert_true(h.is_queued_for_deletion())
	assert_false(service.is_active_for_floor(2),
		"defeat clears the rental so the player must pay again without a floor transition")
	await get_tree().process_frame


func test_damage_resolver_apply_works_against_hooman_data():
	var h := Hooman.new()
	h.hp = 10
	h.max_hp = 10
	h.defense = 1

	var attacker := EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	attacker.attack = 5

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var dealt: int = DamageResolver.apply(attacker, h, rng)

	assert_gt(dealt, 0)
	assert_eq(h.hp, 10 - dealt)
	h.free()
