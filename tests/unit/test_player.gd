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
