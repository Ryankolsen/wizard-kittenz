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
	var prior := gs.local_player_id
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
