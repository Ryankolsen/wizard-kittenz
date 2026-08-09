extends GutTest

const SPEED := 60.0

func test_zero_input_yields_zero_velocity():
	var v := Player.compute_velocity(Vector2.ZERO, SPEED)
	assert_eq(v, Vector2.ZERO, "no input should produce no velocity")

func test_right_input_moves_right():
	var v := Player.compute_velocity(Vector2.RIGHT, SPEED)
	assert_eq(v, Vector2(SPEED, 0.0), "right input should move at +speed on x")

func test_up_input_moves_up():
	var v := Player.compute_velocity(Vector2.UP, SPEED)
	assert_eq(v, Vector2(0.0, -SPEED), "up input should move at -speed on y")

func test_diagonal_preserves_input_magnitude():
	var diag := Vector2(1, 1).normalized()
	var v := Player.compute_velocity(diag, SPEED)
	assert_almost_eq(v.length(), SPEED, 0.001, "normalized diagonal should not exceed speed")

# --- Cross-client TAUNT identity (PRD #124 co-op) ---

func test_player_joins_taunt_targets_group_with_local_id_on_ready():
	# AC: Enemy._select_taunt_target_by_id walks the "taunt_targets" group
	# looking for a player_id match against EnemyData.taunt_source_id. The
	# local Player must register itself there with the autoload's
	# local_player_id, so a self-cast TAUNT (caster's own client) still
	# resolves via the id-match path if taunt_target ever drops out.
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		pending("GameState autoload not present in this test run")
		return
	var prior: String = gs.local_player_id
	gs.local_player_id = "test_local_id"
	var p := Player.new()
	add_child_autofree(p)
	assert_true(p.is_in_group("taunt_targets"),
		"Player._ready must add the node to taunt_targets")
	assert_eq(p.player_id, "test_local_id",
		"blank player_id is populated from GameState.local_player_id on _ready")
	gs.local_player_id = prior

func test_player_id_export_overrides_local_id():
	# AC: tests / future co-op overrides can pre-set player_id; _ready must
	# not clobber a non-empty value.
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.local_player_id = "autoload_id"
	var p := Player.new()
	p.player_id = "preset_id"
	add_child_autofree(p)
	assert_eq(p.player_id, "preset_id",
		"non-blank player_id is preserved across _ready")

# --- GameState injection (issue #150 follow-up) ---

class FakeGameState:
	var local_player_id: String = "injected_id"
	var coop_session = null
	var lobby = null
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character = null
	var skill_tree = null
	var achievement_service = null
	var item_inventory = null

func test_inject_game_state_provides_local_player_id_without_autoload():
	# Demonstrates testability without a running GameState autoload: inject a
	# fake before _ready fires so Player reads its id from the injected object.
	var fake := FakeGameState.new()
	var p := Player.new()
	p._inject_game_state(fake)
	add_child_autofree(p)
	assert_eq(p.player_id, "injected_id",
		"player_id should be populated from injected game state, not the autoload")

func test_inject_game_state_coop_session_returns_null_when_not_set():
	var fake := FakeGameState.new()
	var p := Player.new()
	p._inject_game_state(fake)
	add_child_autofree(p)
	assert_null(p._coop_session(),
		"_coop_session() returns null when injected state has no session")

# --- Quickbar wiring (Slice 2 of PRD #210) ---

func _make_player_with_wizard_tree() -> Player:
	var tree := SkillTree.make_wizard_kitten_tree()
	# Hairball Hex unlocked so the bootstrap has something to fill slot 1
	# with; Catnip Curse unlocked so test_player_does_not_cast_unassigned_...
	# can also observe an unlocked-but-unassigned spell.
	tree.unlock("hairball_hex")
	tree.unlock("catnip_curse")
	var fake := FakeGameState.new()
	fake.skill_tree = tree
	var data := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN)
	# Trivially-affordable MP so cast() succeeds and the deduction is observable.
	data.magic_points = 999
	fake.current_character = data
	var p := Player.new()
	p._inject_game_state(fake)
	add_child_autofree(p)
	return p

func test_player_bootstraps_quickbar_from_unlocked_spells_in_tree_order():
	var p := _make_player_with_wizard_tree()
	# Wizard tree first node (hairball_hex) is unlocked at level 1 by default,
	# so the bootstrap should auto-fill slot 1 with it.
	var qb: Quickbar = p.get_quickbar()
	assert_not_null(qb, "Player must own a Quickbar instance")
	var slot1 := qb.get_slot(1)
	assert_not_null(slot1, "bootstrap should fill slot 1 from the first unlocked spell")
	assert_eq(slot1.id, "hairball_hex",
		"slot 1 should be the wizard's first unlocked spell")

func test_player_casts_through_quickbar_on_cast_slot_1():
	var p := _make_player_with_wizard_tree()
	var qb: Quickbar = p.get_quickbar()
	var hairball = qb.get_slot(1)
	var mp_before := p.data.magic_points
	p._quickbar_controller.try_fire_slot(1)
	assert_lt(p.data.magic_points, mp_before,
		"casting via Quickbar must deduct MP")
	assert_gt(hairball.cooldown_remaining, 0.0,
		"casting via Quickbar must start the spell cooldown")

# --- Cast-channel wiring (issue #476) ---

func _channeled_spell(cast_time: float = 15.0) -> Spell:
	var s := Spell.make("test_channeled_spell", "Test Channeled Spell", Spell.EffectKind.BUFF, 0, 1.0)
	s.cast_time = cast_time
	return s

func test_channeled_cast_locks_movement_while_active():
	var p := _make_player_with_wizard_tree()
	var qb: Quickbar = p.get_quickbar()
	qb.assign(2, _channeled_spell(15.0))
	p._quickbar_controller.try_fire_slot(2)
	assert_true(qb.is_channeling(), "starting the channel should lock the player")
	Input.action_press("move_right")
	p._physics_process(0.016)
	Input.action_release("move_right")
	assert_eq(p.velocity, Vector2.ZERO,
		"movement input must be ignored while a cast channel is active")

func test_channeled_cast_blocks_further_quickbar_casts_while_active():
	var p := _make_player_with_wizard_tree()
	var qb: Quickbar = p.get_quickbar()
	qb.assign(2, _channeled_spell(15.0))
	p._quickbar_controller.try_fire_slot(2)
	var hairball = qb.get_slot(1)
	var mp_before := p.data.magic_points
	p._quickbar_controller.try_fire_slot(1)
	assert_eq(p.data.magic_points, mp_before,
		"a second slot cannot be fired while a channel is active")
	assert_eq(hairball.cooldown_remaining, 0.0)

func test_taking_damage_cancels_channel_and_allows_immediate_retry():
	var p := _make_player_with_wizard_tree()
	var qb: Quickbar = p.get_quickbar()
	var spell := _channeled_spell(15.0)
	qb.assign(2, spell)
	p._quickbar_controller.try_fire_slot(2)
	qb.tick(5.0)
	p.take_damage(1, Vector2.ZERO)
	assert_false(qb.is_channeling(), "damage must cancel the active channel")
	assert_eq(spell.cooldown_remaining, 0.0, "a cancelled channel must not consume a cooldown")
	assert_true(p._quickbar_controller.try_fire_slot(2),
		"the player may attempt to cast again immediately after an interrupted cast")

func test_uninterrupted_channel_completes_without_error():
	var p := _make_player_with_wizard_tree()
	var qb: Quickbar = p.get_quickbar()
	var spell := _channeled_spell(15.0)
	qb.assign(2, spell)
	p._quickbar_controller.try_fire_slot(2)
	qb.tick(15.0)
	assert_false(qb.is_channeling())
	assert_gt(spell.cooldown_remaining, 0.0,
		"an uninterrupted channel completes and consumes the cooldown")

# --- Self-heal counter wiring (PRD #453 / issue #461) ---

func _add_spell_hitbox(p: Player) -> void:
	var hitbox := Area2D.new()
	hitbox.name = "SpellHitbox"
	p.add_child(hitbox)
	p._spell_hitbox = hitbox

func test_self_heal_increments_counter_by_actual_amount_healed():
	var p := _make_player_with_wizard_tree()
	_add_spell_hitbox(p)
	p.data.hp = 1
	p.data.max_hp = 100
	p.data.magic_attack = 0
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var heal_spell := Spell.make("test_heal", "Test Heal", Spell.EffectKind.HEAL, 30, 1.0)
	p._apply_spell_effect(heal_spell)
	assert_eq(int(service.account.achievement_counters.get("self_heal_total", 0)), 30,
		"self_heal_total must increment by the actual HP healed, not a flat 1")

func test_self_heal_at_max_hp_does_not_increment_counter():
	var p := _make_player_with_wizard_tree()
	_add_spell_hitbox(p)
	p.data.max_hp = 100
	p.data.hp = 100
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var heal_spell := Spell.make("test_heal", "Test Heal", Spell.EffectKind.HEAL, 30, 1.0)
	p._apply_spell_effect(heal_spell)
	assert_eq(int(service.account.achievement_counters.get("self_heal_total", 0)), 0,
		"a heal that raises no HP (already at max) must not increment self_heal_total")

# --- Damage-dealt counter wiring (PRD #453 / issue #462) ---

func test_record_damage_dealt_increments_counter_by_actual_amount():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	p._record_damage_dealt(42)
	assert_eq(int(service.account.achievement_counters.get("damage_dealt", 0)), 42,
		"damage_dealt must increment by the actual damage dealt, not a flat 1")
	p._record_damage_dealt(8)
	assert_eq(int(service.account.achievement_counters.get("damage_dealt", 0)), 50,
		"damage_dealt must accumulate across multiple hits")

func test_record_damage_dealt_zero_amount_does_not_increment_counter():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	p._record_damage_dealt(0)
	assert_eq(int(service.account.achievement_counters.get("damage_dealt", 0)), 0,
		"a zero-damage hit (miss/evade) must not increment damage_dealt")

# --- Deaths counter + Second Wind wiring (PRD #453 / issue #466) ---

func test_death_increments_deaths_counter_and_fires_died_once():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var died_count := [0]
	p.died.connect(func(): died_count[0] += 1)
	p.data.hp = 0
	p._check_died()
	assert_eq(int(service.account.achievement_counters.get("deaths", 0)), 1,
		"a real death must increment the deaths counter by 1")
	assert_eq(died_count[0], 1, "died must fire exactly once")
	p._check_died()
	assert_eq(int(service.account.achievement_counters.get("deaths", 0)), 1,
		"a second _check_died call on the same death must not double-increment")
	assert_eq(died_count[0], 1, "died must not re-fire once already emitted")

func test_second_wind_saves_at_one_hp_and_does_not_increment_deaths_when_equipped():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("nine_lives_collar"))
	p._game_state.item_inventory = inv
	var died_count := [0]
	p.died.connect(func(): died_count[0] += 1)
	p.data.hp = 0
	p._check_died()
	assert_eq(p.data.hp, 1, "Second Wind must set HP to 1 instead of letting the wearer die")
	assert_eq(died_count[0], 0, "Second Wind must prevent died from firing on the saved hit")
	assert_eq(int(service.account.achievement_counters.get("deaths", 0)), 0,
		"a hit saved by Second Wind must not increment the deaths counter")

func test_second_wind_does_not_stack_within_a_run():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("nine_lives_collar"))
	p._game_state.item_inventory = inv
	p.data.hp = 0
	p._check_died()
	var died_count := [0]
	p.died.connect(func(): died_count[0] += 1)
	p.data.hp = 0
	p._check_died()
	assert_eq(died_count[0], 1, "a second lethal hit in the same run must fire died normally")
	assert_eq(int(service.account.achievement_counters.get("deaths", 0)), 1,
		"the second lethal hit in the same run must increment the deaths counter")

func test_second_wind_resets_on_new_run():
	# A fresh Player (as produced by the scene reload on floor advance) must
	# be able to trigger Second Wind again even though a prior Player already
	# consumed it, since _second_wind_used lives on the instance.
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("nine_lives_collar"))
	var used_p := _make_player_with_wizard_tree()
	used_p._game_state.item_inventory = inv
	used_p.data.hp = 0
	used_p._check_died()
	assert_eq(used_p.data.hp, 1, "sanity: Second Wind consumed on the first Player")
	var new_p := _make_player_with_wizard_tree()
	new_p._game_state.item_inventory = inv
	new_p.data.hp = 0
	new_p._check_died()
	assert_eq(new_p.data.hp, 1, "a new Player instance (new dungeon run) must be able to trigger Second Wind again")

# --- Idle/late-night/full-Epic-loadout one-offs (PRD #453 / issue #472) ---

func test_idle_tracker_firing_triggers_nap_time_via_player():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var inv := ItemInventory.new()
	p._game_state.item_inventory = inv
	assert_true(p._idle_tracker.advance(IdleTracker.IDLE_THRESHOLD_SECONDS, false),
		"sanity: the idle tracker itself must report the threshold crossed")
	p._record_idle_nap()
	assert_true(service.account.achievement_state.has("nap_time"),
		"the idle-timer firing must record the idle_5min event and unlock Nap Time")
	var claimed := service.claim("nap_time", null, null, null, inv)
	assert_not_null(claimed)
	var bag_ids: Array = []
	for item in inv.bag_items():
		bag_ids.append(item.id)
	assert_true(bag_ids.has("cozy_blanket"), "Nap Time must grant Cozy Blanket to the earning cat's bag")

func test_record_late_night_triggers_three_am_kitten():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	p._record_late_night()
	assert_true(service.account.achievement_state.has("three_am_kitten"),
		"a late-night detection must record the late_night_play event")

func test_maximum_zoomies_requires_all_three_slots_epic():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var inv := ItemInventory.new()
	p._game_state.item_inventory = inv
	inv.equip(ItemCatalog.find("fungal_cap"))
	inv.equip(ItemCatalog.find("alchemists_flask"))
	p._check_maximum_zoomies()
	assert_false(service.account.achievement_state.has("maximum_zoomies"),
		"an empty weapon slot must not unlock Maximum Zoomies")

func test_maximum_zoomies_unlocks_once_all_three_slots_are_epic():
	var p := _make_player_with_wizard_tree()
	var service := AchievementService.new(AccountSaveData.new(), AchievementCatalog.all())
	p._game_state.achievement_service = service
	var inv := ItemInventory.new()
	p._game_state.item_inventory = inv
	inv.equip(ItemCatalog.find("fungal_cap"))
	inv.equip(ItemCatalog.find("alchemists_flask"))
	p._check_maximum_zoomies()
	assert_false(service.account.achievement_state.has("maximum_zoomies"))
	var epic_weapon := ItemData.make("test_epic_weapon", "Test Epic Weapon", ItemData.Slot.WEAPON, ItemData.Rarity.EPIC, "attack", 10.0, [])
	inv.equip(epic_weapon)
	p._check_maximum_zoomies()
	assert_true(service.account.achievement_state.has("maximum_zoomies"),
		"equipping the third Epic slot must unlock Maximum Zoomies")
	watch_signals(service)
	p._check_maximum_zoomies()
	assert_signal_not_emitted(service, "achievement_unlocked",
		"re-checking an already-full Epic loadout must not re-unlock Maximum Zoomies")

func test_player_does_not_cast_unassigned_unlocked_spell():
	# Pin the old "first ready unlocked spell wins" behavior is gone: a spell
	# that is unlocked but explicitly removed from every slot must NOT fire
	# when any cast_slot_N is fired.
	var p := _make_player_with_wizard_tree()
	var qb: Quickbar = p.get_quickbar()
	# Clear slot 1 (which the bootstrap filled with hairball_hex).
	var hairball = qb.get_slot(1)
	qb.unassign(1)
	assert_null(qb.get_slot(1))
	var mp_before := p.data.magic_points
	p._quickbar_controller.try_fire_slot(1)
	assert_eq(p.data.magic_points, mp_before,
		"empty slot must not consume MP")
	assert_eq(hairball.cooldown_remaining, 0.0,
		"empty slot must not trigger the unlocked spell's cooldown")
