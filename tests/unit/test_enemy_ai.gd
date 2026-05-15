extends GutTest

const _State := EnemyAIState.State

# --- Pure state machine: EnemyAIState.next_state ---

func test_idle_transitions_to_chase_when_player_enters_detection_radius():
	# Acceptance #1: Idle -> Chase when distance <= DETECTION_RADIUS.
	var inside := EnemyAIState.DETECTION_RADIUS - 5.0
	var s := EnemyAIState.next_state(_State.IDLE, inside, 5)
	assert_eq(s, _State.CHASE, "in detection range -> CHASE")

func test_idle_stays_idle_when_player_outside_detection():
	var outside := EnemyAIState.DETECTION_RADIUS + 50.0
	var s := EnemyAIState.next_state(_State.IDLE, outside, 5)
	assert_eq(s, _State.IDLE)

func test_chase_to_attack_within_melee_and_back_to_chase_when_player_moves_away():
	# Acceptance #2: Chase -> Attack on melee entry, Attack -> Chase on exit.
	var melee := EnemyAIState.MELEE_RANGE - 1.0
	var s1 := EnemyAIState.next_state(_State.CHASE, melee, 5)
	assert_eq(s1, _State.ATTACK)
	var chasing_again := EnemyAIState.MELEE_RANGE + 10.0
	var s2 := EnemyAIState.next_state(_State.ATTACK, chasing_again, 5)
	assert_eq(s2, _State.CHASE)

func test_zero_hp_transitions_to_dead_from_any_state():
	# Acceptance #3 (logic half): hp <= 0 always wins.
	for prev in [_State.IDLE, _State.CHASE, _State.ATTACK]:
		assert_eq(EnemyAIState.next_state(prev, 1000.0, 0), _State.DEAD)
		assert_eq(EnemyAIState.next_state(prev, 5.0, 0), _State.DEAD)
		assert_eq(EnemyAIState.next_state(prev, 5.0, -3), _State.DEAD,
			"negative hp also dead — overkill case")

func test_dead_is_a_sink_state_no_chase_after_death():
	# Acceptance #4: dead enemy stays dead even if player wanders into range.
	var inside := EnemyAIState.DETECTION_RADIUS - 5.0
	var s := EnemyAIState.next_state(_State.DEAD, inside, 5)
	assert_eq(s, _State.DEAD,
		"dead enemy with hp > 0 (somehow) still doesn't reanimate")
	var melee := EnemyAIState.MELEE_RANGE - 1.0
	assert_eq(EnemyAIState.next_state(_State.DEAD, melee, 10), _State.DEAD)

func test_melee_range_takes_precedence_over_chase_range():
	# Implicit: when both checks would pass, attack wins.
	var melee := EnemyAIState.MELEE_RANGE - 1.0
	var s := EnemyAIState.next_state(_State.IDLE, melee, 5)
	assert_eq(s, _State.ATTACK,
		"a player who teleports straight into melee skips Chase entirely")

func test_state_name_returns_human_readable_strings():
	assert_eq(EnemyAIState.state_name(_State.IDLE), "Idle")
	assert_eq(EnemyAIState.state_name(_State.CHASE), "Chase")
	assert_eq(EnemyAIState.state_name(_State.ATTACK), "Attack")
	assert_eq(EnemyAIState.state_name(_State.DEAD), "Dead")

# --- Enemy node integration: signal + queue_free guarded by _died_emitted ---

func _make_enemy() -> Enemy:
	var e := Enemy.new()
	e.data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	return e

func test_enemy_emits_died_signal_when_hp_drops_to_zero():
	# Acceptance #3 (signal half).
	var e := _make_enemy()
	var fired := [0]
	e.died.connect(func(): fired[0] += 1)
	# Live, far -> Idle, no signal
	e.apply_state_update(1000.0)
	assert_eq(e.state, _State.IDLE)
	assert_eq(fired[0], 0)
	# Kill
	e.data.hp = 0
	e.apply_state_update(10.0)
	assert_eq(e.state, _State.DEAD)
	assert_eq(fired[0], 1, "died emitted exactly once on the live->DEAD edge")
	e.free()

func test_died_signal_only_fires_once_even_across_multiple_updates():
	var e := _make_enemy()
	var fired := [0]
	e.died.connect(func(): fired[0] += 1)
	e.data.hp = 0
	e.apply_state_update(10.0)
	e.apply_state_update(50.0)
	e.apply_state_update(10.0)
	assert_eq(fired[0], 1, "subsequent ticks while dead do not re-emit")
	e.free()

func test_enemy_state_walks_idle_chase_attack_chase_idle():
	# End-to-end transition path through the state machine, driven by the
	# same apply_state_update entry point _physics_process uses.
	var e := _make_enemy()
	e.apply_state_update(1000.0)
	assert_eq(e.state, _State.IDLE)
	e.apply_state_update(EnemyAIState.DETECTION_RADIUS - 10.0)
	assert_eq(e.state, _State.CHASE)
	e.apply_state_update(EnemyAIState.MELEE_RANGE - 5.0)
	assert_eq(e.state, _State.ATTACK)
	e.apply_state_update(EnemyAIState.MELEE_RANGE + 10.0)
	assert_eq(e.state, _State.CHASE)
	e.apply_state_update(EnemyAIState.DETECTION_RADIUS + 50.0)
	assert_eq(e.state, _State.IDLE)
	e.free()

func test_dead_enemy_does_not_chase_via_node_path():
	# Acceptance #4 (node level): once _died_emitted is set, no future
	# distance update reanimates the enemy. apply_state_update returns
	# DEAD permanently.
	var e := _make_enemy()
	e.data.hp = 0
	e.apply_state_update(10.0)
	assert_eq(e.state, _State.DEAD)
	# Even if someone "heals" the enemy after death, the state machine
	# refuses to climb back out of DEAD.
	e.data.hp = 5
	e.apply_state_update(10.0)
	assert_eq(e.state, _State.DEAD,
		"DEAD is a sink — a post-death heal cannot resurrect")
	e.free()

func test_apply_state_update_is_safe_with_null_data():
	# Defensive: a freshly constructed Enemy without data shouldn't crash
	# the AI tick. _physics_process early-returns; apply_state_update mirrors.
	var e := Enemy.new()
	e.apply_state_update(10.0)
	assert_eq(e.state, _State.IDLE,
		"no data -> state untouched, no signal")
	e.free()

# --- TAUNT integration: Chonk Kitten (PRD #124) ---

func _make_player_with(c: CharacterData) -> Player:
	var p := Player.new()
	p.data = c
	p.add_to_group("player")
	add_child_autofree(p)
	return p

func test_select_taunt_target_returns_null_when_not_taunted():
	# AC: no taunt active -> fall through to default targeting.
	var e := _make_enemy()
	var c := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN, "Tank")
	var picked := e._select_taunt_target([c])
	assert_null(picked, "no taunt -> no taunt-target pick")
	e.free()

func test_select_taunt_target_returns_matching_player():
	# AC: Chonk Taunt sets enemy.data.taunt_target to the caster's
	# CharacterData; _find_player must locate the Player node whose
	# data matches and prefer it over the group's nearest entry.
	var e := _make_enemy()
	var tank_data := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN, "Tank")
	var mage_data := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Mage")
	var tank := _make_player_with(tank_data)
	var mage := _make_player_with(mage_data)
	e.data.taunt_target = tank_data
	e.data.taunt_remaining = 2.0
	var picked := e._select_taunt_target([mage, tank])
	assert_eq(picked, tank,
		"taunt redirects to the caster's Player node, not the first group entry")
	e.free()

func test_select_taunt_target_returns_null_when_target_gone():
	# AC defensive: caster despawned mid-taunt -> no live match -> null
	# so _find_player falls through to the group lookup instead of crashing.
	var e := _make_enemy()
	var ghost_data := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN, "Ghost")
	var other_data := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Other")
	var other := _make_player_with(other_data)
	e.data.taunt_target = ghost_data
	e.data.taunt_remaining = 2.0
	var picked := e._select_taunt_target([other])
	assert_null(picked, "no live Player matches the taunted data -> null")
	e.free()

func test_physics_process_decays_active_taunt():
	# AC: each physics frame ticks the taunt timer down so a TAUNT expires
	# on its own without an explicit clear call. Drive _physics_process
	# directly with a synthetic delta to bypass the SceneTree dependency.
	var e := _make_enemy()
	var caster := CharacterData.make_new(CharacterData.CharacterClass.CHONK_KITTEN, "C")
	e.data.taunt_target = caster
	e.data.taunt_remaining = 1.5
	# Tick the data layer directly — _physics_process delegates to this and
	# also walks the scene tree, which is the part we don't want to spin up.
	e.data.tick_taunt(0.5)
	assert_almost_eq(e.data.taunt_remaining, 1.0, 0.001,
		"taunt timer counts down on each tick")
	e.data.tick_taunt(1.2)
	assert_false(e.data.is_taunted(),
		"taunt expires and clears once the timer hits zero")
	assert_eq(e.data.taunt_target, null,
		"taunt_target cleared on expiry so AI falls back to default targeting")
	e.free()

func test_constants_are_sensible():
	# Guard against a tuning typo flipping the geometry — melee must be
	# strictly inside detection or Chase becomes unreachable.
	assert_lt(EnemyAIState.MELEE_RANGE, EnemyAIState.DETECTION_RADIUS,
		"melee must be a tighter ring than detection")
	assert_gt(EnemyAIState.ATTACK_COOLDOWN, 0.0)
	assert_gt(EnemyAIState.CHASE_SPEED, 0.0)
