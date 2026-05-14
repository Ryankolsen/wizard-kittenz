extends GutTest

# Tests for the main_scene → CoopSession activation wire added alongside
# the kill / position / seed slices. Before this wire, lobby.gd's
# _on_match_started constructed CoopSession but never called start() —
# session.is_active() was always false, so:
#   - KillRewardRouter.is_coop_route returned false → no OP_KILL sent
#   - session.enemy_sync was null → register_room_enemies was a no-op
#   - session.position_broadcast_gate was null → no position packets
# Every prior co-op slice's "data layer wired" claim depended on tests
# explicitly calling session.start(); production never did. These tests
# pin that main_scene._ready activates the session and registers the
# current room's enemy_id with session.enemy_sync.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

# --- helpers ---------------------------------------------------------------

func _make_coop_session() -> CoopSession:
	# Mirrors lobby.gd's _on_match_started shape: a one-player lobby with
	# this client's CharacterData mapped under local_player_id. The session
	# is constructed but NOT yet active — that's what main_scene._ready is
	# supposed to fix.
	var ls := LobbyState.new("ABCDE")
	ls.add_player(LobbyPlayer.make("p1", "Whiskers", "Mage", true))
	var c := CharacterFactory.create_default("Mage")
	return CoopSession.new(ls, {"p1": c}, MetaProgressionTracker.new(), "p1")

func _install_session(session: CoopSession) -> void:
	var gs := get_node("/root/GameState")
	gs.coop_session = session
	gs.local_player_id = "p1"
	# Fresh run_controller is what main_scene._start_new_dungeon mints; clear
	# any leftover from a previous test so the new-dungeon branch fires.
	gs.dungeon_run_controller = null

# --- lifecycle -------------------------------------------------------------

func before_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		# Tear down any live session before each test so start() can fire
		# fresh. end() is idempotent — returns false if already inactive.
		if gs.coop_session != null and gs.coop_session.is_active():
			gs.coop_session.end()
		gs.coop_session = null
		gs.dungeon_run_controller = null
		gs.local_player_id = ""

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		if gs.coop_session != null and gs.coop_session.is_active():
			gs.coop_session.end()
		gs.coop_session = null
		gs.dungeon_run_controller = null
		gs.local_player_id = ""

# --- tests -----------------------------------------------------------------

func test_main_scene_activates_coop_session_on_ready():
	# Closes the critical gap: before this wire, session was constructed
	# in lobby.gd but never start()'d, so the entire wire layer (kill XP,
	# position, enemy sync) silently no-op'd. Pin that loading the
	# gameplay scene flips the session active.
	var session := _make_coop_session()
	_install_session(session)
	assert_false(session.is_active(),
		"precondition: session is constructed but inactive")

	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	assert_true(session.is_active(),
		"main_scene._ready must call session.start(dungeon)")
	assert_not_null(session.enemy_sync,
		"start() builds enemy_sync — the registry the wire layer reads")
	assert_not_null(session.xp_broadcaster,
		"start() builds xp_broadcaster — the XP fan-out subject")
	assert_not_null(session.position_broadcast_gate,
		"start() builds position_broadcast_gate — Player reads this each tick")

func test_main_scene_registers_all_combat_enemies_with_session():
	# Issue #96: every combat room's enemy_id must be registered with
	# session.enemy_sync at dungeon load (not lazily on room enter), so the
	# remote-kill receive path's apply_death rising-edges true regardless of
	# which room the death packet refers to. Pin that the registry contains
	# one id per STANDARD + BOSS room and zero ids for non-combat rooms.
	var session := _make_coop_session()
	_install_session(session)

	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	var rc: DungeonRunController = get_node("/root/GameState").dungeon_run_controller
	assert_not_null(rc, "main_scene must install the run controller")
	var combat_count := 0
	for r in rc.dungeon.rooms:
		if r.type == Room.TYPE_STANDARD or r.type == Room.TYPE_BOSS:
			combat_count += 1
			assert_true(session.enemy_sync.is_alive("r%d_e0" % r.id),
				"enemy_sync must contain combat room %d's planned id" % r.id)
	assert_eq(session.enemy_sync.alive_count(), combat_count,
		"registry has exactly one id per combat room — no over- or under-registration")

func test_main_scene_solo_path_does_not_crash_with_null_session():
	# Solo / pre-handshake / no-multiplayer path: coop_session is null.
	# The activation branch is guarded; main_scene._ready must still build
	# the dungeon and enter the start room without crashing.
	_install_session(null)

	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	var gs := get_node("/root/GameState")
	assert_null(gs.coop_session,
		"solo path leaves coop_session null")
	assert_not_null(gs.dungeon_run_controller,
		"solo path still installs a run controller")

func test_main_scene_reload_keeps_active_session():
	# Scene reload after advance_to (_on_next_room_requested calls
	# get_tree().reload_current_scene()) re-runs main_scene._ready.
	# session.start is idempotent — a second call returns false without
	# clobbering the existing managers. Pin that the wire's idempotency
	# survives the reload pattern.
	var session := _make_coop_session()
	_install_session(session)

	var first: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(first)
	assert_true(session.is_active())
	var first_enemy_sync := session.enemy_sync

	# Simulate the reload: gs.dungeon_run_controller stays non-null
	# between reloads (the controller survives so the player resumes on
	# the same room), so _start_new_dungeon is skipped and session.start
	# is NOT re-invoked. Drop the first scene to mirror reload teardown.
	first.queue_free()

	var second: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(second)
	assert_true(session.is_active(),
		"second main_scene._ready must not deactivate the session")
	assert_same(session.enemy_sync, first_enemy_sync,
		"reloading the scene must reuse the original enemy_sync — a new "
		+ "instance would drop every registered id and break the wire")

func test_main_scene_with_pre_existing_run_controller_does_not_re_activate():
	# When gs.dungeon_run_controller is already set (mid-run reload),
	# main_scene takes the resume branch and skips _start_new_dungeon —
	# so the activation hook is never re-run. Pin that this path doesn't
	# rebuild the session managers either.
	var session := _make_coop_session()
	_install_session(session)
	# Pre-activate the session with a tiny dungeon so the resume branch
	# fires without crashing. main_scene reads gs.dungeon_run_controller,
	# which we set to a fresh controller against the same dungeon.
	var d := _tiny_dungeon()
	session.start(d)
	var rc := DungeonRunController.new()
	rc.start(d)
	var gs := get_node("/root/GameState")
	gs.dungeon_run_controller = rc
	var enemy_sync_before := session.enemy_sync

	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	assert_true(session.is_active(),
		"session stays active across scene reload")
	assert_same(session.enemy_sync, enemy_sync_before,
		"resume-branch _ready must NOT rebuild enemy_sync — the wire's "
		+ "registered ids would otherwise vanish on every room advance")

# --- finalize-on-dungeon-complete (#17 AC#5) -------------------------------
# Closes the snapshot side of AC#5. Before _finalize_completed_run was
# extracted, main_scene._on_dungeon_completed reloaded the scene without
# capturing the live xp_summary anywhere — the future summary screen
# (#33 / HITL render surface) had nothing to read. After this wire, the
# session freezes its rows + header before the reload so the screen
# can render them from gs.coop_session.last_run_summary_*.

func test_finalize_completed_run_captures_session_snapshot():
	var session := _make_coop_session()
	_install_session(session)

	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	# Fan some XP through the session's broadcaster so the snapshot has
	# something to capture (vs. a clear-room dungeon with zero XP).
	session.xp_broadcaster.on_enemy_killed(15)

	# Pre-finalize: snapshot is empty, completion flag false.
	assert_false(session.was_dungeon_completed())
	assert_eq(session.last_run_summary_header, {})

	# Drive the testable seam directly (the production handler also calls
	# reload_current_scene, which would clobber the GUT runner).
	inst._finalize_completed_run()

	assert_true(session.was_dungeon_completed(),
		"finalize sets the dungeon-complete flag")
	assert_eq(session.last_run_summary_rows.size(), 1,
		"one row per party member")
	assert_eq(session.last_run_summary_header.get("grand_total_xp"), 15,
		"snapshot reflects the live xp_summary at finalize time")
	assert_true(session.last_run_summary_header.get("dungeon_completed"),
		"header carries the victory flag")

func test_finalize_completed_run_solo_path_is_safe_with_null_session():
	# Solo / pre-handshake: coop_session is null. The finalize seam must
	# still advance the meta tracker and clear the run controller without
	# crashing on the missing session.
	_install_session(null)

	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	var gs := get_node("/root/GameState")
	var pre_completed: int = gs.meta_tracker.dungeons_completed
	assert_not_null(gs.dungeon_run_controller,
		"precondition: solo path installed a run controller")

	inst._finalize_completed_run()

	assert_eq(gs.meta_tracker.dungeons_completed, pre_completed + 1,
		"meta tracker bumps on solo finalize")
	assert_null(gs.dungeon_run_controller,
		"run controller cleared so the next _ready takes the new-dungeon branch")

func test_finalize_completed_run_clears_run_controller_for_next_run():
	# After finalize, gs.dungeon_run_controller must be null so the next
	# main_scene._ready takes the _start_new_dungeon branch (a fresh
	# dungeon for the next run) rather than the resume branch (which
	# would reuse the just-completed dungeon).
	var session := _make_coop_session()
	_install_session(session)

	var inst: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child_autofree(inst)

	var gs := get_node("/root/GameState")
	assert_not_null(gs.dungeon_run_controller,
		"precondition: _ready installed a run controller")

	inst._finalize_completed_run()

	assert_null(gs.dungeon_run_controller,
		"finalize clears the run controller")

# --- helpers (cont.) -------------------------------------------------------

func _tiny_dungeon() -> Dungeon:
	# Smallest dungeon that satisfies session.start()'s + DungeonRunController's
	# preconditions: a start room with a connection to a boss room. Mirrors
	# the shape used in test_coop_session.gd's start-helper.
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.RAT
	d.add_room(start)
	d.add_room(boss)
	d.start_id = 0
	d.boss_id = 1
	return d
