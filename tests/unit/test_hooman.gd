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


# --- Briefcase combat (issue #499) ----------------------------------------

func _make_target_enemy() -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.ANGRY_PIGEON)
	e.data.defense = 0
	return e

# Advances the choreographer through a full windup+strike+recovery cycle in
# one call so tests don't need to hand-step individual phase durations.
# `dist` re-feeds the same distance-to-mob used to enter ATTACK so the state
# machine doesn't flip elsewhere mid-swing.
func _run_full_swing(h: Hooman, dist: float) -> void:
	var def := WeaponDefinition.briefcase()
	h.tick(def.total_duration() + 0.01, Vector2.ZERO, dist, 1.0, true, h._current_target)

func test_briefcase_definition_uses_swing_attack_type():
	assert_eq(WeaponDefinition.briefcase().attack_type, WeaponDefinition.AttackType.SWING)

func test_briefcase_definition_texture_path():
	assert_eq(WeaponDefinition.briefcase().texture_path, "res://assets/sprites/weapon_briefcase_sprite.png")

func test_attack_state_deals_damage_to_nearest_mob():
	var h := Hooman.new()
	h.attack = 20
	h.global_position = Vector2.ZERO
	var target := _make_target_enemy()
	target.global_position = Vector2(HoomanAIState.MELEE_RANGE - 1.0, 0.0)
	var start_hp: int = target.data.hp

	h.tick(0.016, Vector2.ZERO, 0.0, 1.0, true, target)
	assert_eq(h.state, HoomanAIState.State.ATTACK)
	# HitResolver's base 85% hit chance (uses the global randf(), same as
	# production) means a single swing can whiff; retry swings rather than
	# asserting on one non-deterministic roll — matches
	# test_try_contact_damage_applies_to_hooman's retry pattern.
	for i in range(20):
		_run_full_swing(h, 0.0)
		if target.data.hp < start_hp:
			break

	assert_lt(target.data.hp, start_hp, "strike window should have damaged the nearest in-range mob")
	h.free()
	target.free()

func test_attack_does_not_damage_mob_out_of_melee_range():
	var h := Hooman.new()
	h.attack = 20
	h.global_position = Vector2.ZERO
	var target := _make_target_enemy()
	target.global_position = Vector2(HoomanAIState.MELEE_RANGE + 50.0, 0.0)
	var start_hp: int = target.data.hp

	# distance_to_mob for the state decision is the mob's actual distance
	# (beyond melee range), so the hooman lands in CHASE, not ATTACK — no
	# strike ever fires, and hp is untouched either way.
	var dist := HoomanAIState.MELEE_RANGE + 50.0
	h.tick(0.016, Vector2.ZERO, dist, 1.0, true, target)
	assert_eq(h.state, HoomanAIState.State.CHASE)
	_run_full_swing(h, dist)

	assert_eq(target.data.hp, start_hp, "mob outside melee range takes no damage")
	h.free()
	target.free()

func test_killing_mob_via_hooman_emits_died_signal():
	var h := Hooman.new()
	h.attack = 999
	h.global_position = Vector2.ZERO
	var target := _make_target_enemy()
	target.global_position = Vector2(HoomanAIState.MELEE_RANGE - 1.0, 0.0)
	target.data.hp = 1
	var fired := [0]
	target.died.connect(func(): fired[0] += 1)

	h.tick(0.016, Vector2.ZERO, 0.0, 1.0, true, target)
	# Same 85%-hit-chance retry rationale as test_attack_state_deals_damage_
	# to_nearest_mob — keep swinging until the one-hp killing blow lands.
	for i in range(20):
		_run_full_swing(h, 0.0)
		if not target.data.is_alive():
			break
	target.apply_state_update(1000.0)

	assert_eq(fired[0], 1, "died emitted exactly once on the hooman's killing blow")
	h.free()
	target.free()


# --- Burst heal (issue #500) -----------------------------------------------

# Node-based player stand-in (not a plain RefCounted mock) so
# FloatingText.spawn's target_node.add_child(ft) call works the same as it
# does against the real Player node in production.
class _MockPlayer:
	extends Node
	var data: CharacterData

func _make_player(hp: int, max_hp: int) -> Node:
	var p := _MockPlayer.new()
	p.data = CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	p.data.max_hp = max_hp
	p.data.hp = hp
	return p

func test_heal_state_heals_player_by_burst_amount():
	var h := Hooman.new()
	var player := _make_player(1, 50)

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)

	assert_eq(h.state, HoomanAIState.State.HEAL, "low player HP percent should route the hooman into HEAL")
	assert_eq(player.data.hp, 1 + HoomanAIState.HEAL_BURST_AMOUNT)
	h.free()
	player.free()


func test_heal_does_not_overheal_beyond_max_hp():
	var h := Hooman.new()
	var max_hp := 10
	var player := _make_player(max_hp - 1, max_hp)

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)

	assert_eq(player.data.hp, max_hp, "heal is capped at max_hp even though the burst amount would overheal")
	h.free()
	player.free()


func test_heal_does_not_refire_before_cooldown_elapses():
	var h := Hooman.new()
	var player := _make_player(1, 50)

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)
	var hp_after_first: int = player.data.hp

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)

	assert_eq(player.data.hp, hp_after_first,
		"second heal within HEAL_COOLDOWN seconds of the first should not fire")
	h.free()
	player.free()


func test_heal_fires_again_after_cooldown_elapses():
	var h := Hooman.new()
	var player := _make_player(1, 50)

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)
	var hp_after_first: int = player.data.hp

	h.tick(HoomanAIState.HEAL_COOLDOWN + 0.01, Vector2.ZERO, INF, 0.02, true, null, player)

	assert_eq(player.data.hp, hp_after_first + HoomanAIState.HEAL_BURST_AMOUNT,
		"heal should fire again once HEAL_COOLDOWN seconds have elapsed since the last one")
	h.free()
	player.free()


# --- HEAL-state glow telegraph (issue #503) -----------------------------

func test_heal_state_shows_glow_effect():
	var h := Hooman.new()
	var player := _make_player(1, 50)

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)

	assert_eq(h.state, HoomanAIState.State.HEAL)
	assert_true(h.get_heal_glow().emitting, "glow effect should be emitting while in HEAL state")
	h.free()
	player.free()


func test_glow_effect_hidden_when_leaving_heal_state():
	var h := Hooman.new()
	var player := _make_player(1, 50)

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)
	assert_true(h.get_heal_glow().emitting)

	h.tick(0.016, Vector2.ZERO, 5.0, 0.1, false)

	assert_eq(h.state, HoomanAIState.State.FOLLOW)
	assert_false(h.get_heal_glow().emitting, "glow effect should stop emitting once the hooman leaves HEAL")
	h.free()
	player.free()


func test_glow_effect_off_when_never_entering_heal():
	var h := Hooman.new()
	h.tick(0.016, Vector2.ZERO, 50.0, 0.9, true)
	assert_eq(h.state, HoomanAIState.State.CHASE)
	assert_false(h.get_heal_glow().emitting, "glow effect should not be on by default outside HEAL")
	h.free()


func test_glow_stays_visible_during_heal_cooldown():
	var h := Hooman.new()
	var player := _make_player(1, 50)

	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)
	assert_true(h.get_heal_glow().emitting)

	# Second tick still routes to HEAL, but the burst is on cooldown so no
	# heal number lands — the glow must still be on.
	h.tick(0.016, Vector2.ZERO, INF, 0.02, true, null, player)

	assert_eq(h.state, HoomanAIState.State.HEAL)
	assert_true(h.get_heal_glow().emitting,
		"glow effect should stay on through the HEAL cooldown window, not just when a heal lands")
	h.free()
	player.free()
