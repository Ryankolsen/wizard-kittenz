extends GutTest

# --- RemotePlayerInterpolator.get_display_position --------------------------

func test_get_display_position_no_samples_returns_zero():
	# Before any sample lands, the remote kitten can't be drawn anywhere
	# meaningful. Returning Vector2.ZERO keeps it off-screen rather than
	# popping in at a stale origin from a recycled interpolator.
	var ri := RemotePlayerInterpolator.new()
	assert_eq(ri.get_display_position(0.5), Vector2.ZERO)
	assert_eq(ri.sample_count(), 0)
	assert_false(ri.has_sample())

func test_get_display_position_single_sample_returns_current():
	# After exactly one sample there's nothing to lerp from. Returning
	# current_position pops the kitten in at the first known location
	# rather than crawling out of (0, 0).
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(10, 20), 1.0)
	assert_eq(ri.get_display_position(0.0), Vector2(10, 20))
	assert_eq(ri.get_display_position(0.5), Vector2(10, 20))
	assert_eq(ri.get_display_position(1.0), Vector2(10, 20))
	assert_eq(ri.sample_count(), 1)

func test_get_display_position_lerps_between_previous_and_current():
	# Issue scenario 2: get_display_position(t) returns a value between
	# the previous and current known positions when t is between 0 and 1.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 2.0)
	assert_eq(ri.get_display_position(0.0), Vector2(0, 0), "t=0 -> previous")
	assert_eq(ri.get_display_position(1.0), Vector2(100, 0), "t=1 -> current")
	assert_eq(ri.get_display_position(0.5), Vector2(50, 0), "t=0.5 -> midpoint")
	assert_eq(ri.get_display_position(0.25), Vector2(25, 0), "t=0.25 -> quarter")

func test_get_display_position_lerp_is_componentwise():
	# Confirms the lerp is Vector2.lerp, not just x-axis.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(10, 20), 1.0)
	ri.push_sample(Vector2(30, 60), 2.0)
	assert_eq(ri.get_display_position(0.5), Vector2(20, 40))

func test_get_display_position_t_clamps_to_unit_range():
	# Defensive against a mis-computed t (e.g. (now - prev_ts) /
	# (curr_ts - prev_ts) when prev_ts == curr_ts -> div-by-zero ->
	# inf/nan upstream). Clamping inside get_display_position means a
	# bad t never produces an out-of-bounds extrapolated position.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 2.0)
	assert_eq(ri.get_display_position(-0.5), Vector2(0, 0), "t<0 clamps to previous")
	assert_eq(ri.get_display_position(2.0), Vector2(100, 0), "t>1 clamps to current")

func test_push_sample_shifts_current_to_previous():
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(10, 10), 1.0)
	ri.push_sample(Vector2(20, 20), 2.0)
	assert_eq(ri.previous_position, Vector2(10, 10))
	assert_eq(ri.current_position, Vector2(20, 20))
	assert_eq(ri.previous_timestamp, 1.0)
	assert_eq(ri.current_timestamp, 2.0)
	assert_eq(ri.sample_count(), 2)

func test_push_sample_third_sample_drops_oldest():
	# Two-slot buffer: a third sample shifts the second into prev and
	# evicts the original. Keeps memory bounded as the wire layer fires
	# state packets every tick.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(50, 0), 2.0)
	ri.push_sample(Vector2(100, 0), 3.0)
	assert_eq(ri.previous_position, Vector2(50, 0))
	assert_eq(ri.current_position, Vector2(100, 0))
	assert_eq(ri.get_display_position(0.5), Vector2(75, 0))

# --- NetworkSyncManager.apply_remote_state ---------------------------------

func test_apply_remote_state_auto_registers_player():
	# Issue scenario 1: apply_remote_state updates the remote player's
	# interpolation target position. First call for an unknown id
	# auto-registers a fresh interpolator.
	var nsm := NetworkSyncManager.new()
	assert_false(nsm.has_player("u2"))
	nsm.apply_remote_state("u2", Vector2(50, 50), 1.0)
	assert_true(nsm.has_player("u2"), "first apply auto-registers")
	assert_eq(nsm.player_count(), 1)
	# The interpolator's current_position is the applied value.
	var interp := nsm.get_interpolator("u2")
	assert_not_null(interp)
	assert_eq(interp.current_position, Vector2(50, 50))

func test_apply_remote_state_second_call_shifts_to_previous():
	var nsm := NetworkSyncManager.new()
	nsm.apply_remote_state("u2", Vector2(0, 0), 1.0)
	nsm.apply_remote_state("u2", Vector2(100, 0), 2.0)
	# Lerp at t=0.5 should produce the midpoint, confirming both slots
	# are populated and the second call shifted the first into previous.
	assert_eq(nsm.get_display_position("u2", 0.5), Vector2(50, 0))

func test_apply_remote_state_per_player_isolation():
	# Two remote players don't share interpolation buffers — applying
	# state to u2 doesn't perturb u3's display position.
	var nsm := NetworkSyncManager.new()
	nsm.apply_remote_state("u2", Vector2(10, 10), 1.0)
	nsm.apply_remote_state("u3", Vector2(99, 99), 1.0)
	assert_eq(nsm.get_display_position("u2", 1.0), Vector2(10, 10))
	assert_eq(nsm.get_display_position("u3", 1.0), Vector2(99, 99))
	assert_eq(nsm.player_count(), 2)

func test_apply_remote_state_empty_player_id_rejected():
	# Defensive: a wire payload with a missing id shouldn't quietly
	# create a "" entry that pollutes the registry.
	var nsm := NetworkSyncManager.new()
	var result := nsm.apply_remote_state("", Vector2(10, 10), 1.0)
	assert_null(result)
	assert_eq(nsm.player_count(), 0)

func test_get_display_position_unknown_player_returns_zero():
	var nsm := NetworkSyncManager.new()
	assert_eq(nsm.get_display_position("ghost", 0.5), Vector2.ZERO)

func test_remove_player_drops_interpolator():
	# Lobby's "player left" event drops the interpolator so a
	# disconnected kitten stops occupying state.
	var nsm := NetworkSyncManager.new()
	nsm.apply_remote_state("u2", Vector2(10, 10), 1.0)
	assert_true(nsm.remove_player("u2"))
	assert_false(nsm.has_player("u2"))
	assert_eq(nsm.get_display_position("u2", 0.5), Vector2.ZERO)

func test_remove_player_unknown_id_noop():
	var nsm := NetworkSyncManager.new()
	assert_false(nsm.remove_player("nope"))

func test_clear_drops_all_players():
	var nsm := NetworkSyncManager.new()
	nsm.apply_remote_state("u2", Vector2(10, 10), 1.0)
	nsm.apply_remote_state("u3", Vector2(20, 20), 1.0)
	nsm.clear()
	assert_eq(nsm.player_count(), 0)
	assert_false(nsm.has_player("u2"))

# --- XPBroadcaster.on_enemy_killed -----------------------------------------

func _capture_emissions(broadcaster: XPBroadcaster) -> Array:
	var emissions: Array = []
	broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	return emissions

func test_on_enemy_killed_emits_for_all_registered_players():
	# Issue scenario 3: emits xp_awarded for every registered id with
	# the correct amount, not just the killer.
	var b := XPBroadcaster.new()
	b.register_player("u1")
	b.register_player("u2")
	b.register_player("u3")
	var emissions := _capture_emissions(b)
	b.on_enemy_killed(10, "u2")  # u2 got the killing blow
	assert_eq(emissions.size(), 3, "all 3 registered players got the signal")
	# Every emission carries amount=10, regardless of who the killer was.
	for e in emissions:
		assert_eq(e[1], 10)
	# All three player_ids appear exactly once across emissions.
	var ids: Array = []
	for e in emissions:
		ids.append(e[0])
	assert_true(ids.has("u1"))
	assert_true(ids.has("u2"))
	assert_true(ids.has("u3"))

func test_on_enemy_killed_killer_id_does_not_filter_recipients():
	# Even when the killer is not registered (host-only kill, no
	# player_id reflection), every registered player still receives
	# their share — matching user story 22.
	var b := XPBroadcaster.new()
	b.register_player("u1")
	b.register_player("u2")
	var emissions := _capture_emissions(b)
	b.on_enemy_killed(7, "ghost")
	assert_eq(emissions.size(), 2)

func test_on_enemy_killed_with_no_registered_players_emits_nothing():
	var b := XPBroadcaster.new()
	var emissions := _capture_emissions(b)
	b.on_enemy_killed(10, "u1")
	assert_eq(emissions.size(), 0)

func test_on_enemy_killed_zero_or_negative_xp_is_noop():
	# Same shape as ProgressionSystem.add_xp's negative-amount guard.
	var b := XPBroadcaster.new()
	b.register_player("u1")
	var emissions := _capture_emissions(b)
	b.on_enemy_killed(0, "u1")
	b.on_enemy_killed(-5, "u1")
	assert_eq(emissions.size(), 0)

func test_register_player_increments_count():
	# Issue scenario equivalent to LobbyState.add_player: register adds
	# the id and reports it via player_count.
	var b := XPBroadcaster.new()
	assert_true(b.register_player("u1"))
	assert_eq(b.player_count(), 1)
	assert_true(b.has_player("u1"))

func test_register_player_duplicate_rejected():
	var b := XPBroadcaster.new()
	b.register_player("u1")
	assert_false(b.register_player("u1"), "duplicate rejected")
	assert_eq(b.player_count(), 1)

func test_register_player_empty_id_rejected():
	var b := XPBroadcaster.new()
	assert_false(b.register_player(""))
	assert_eq(b.player_count(), 0)

func test_unregister_player_drops_from_broadcast():
	var b := XPBroadcaster.new()
	b.register_player("u1")
	b.register_player("u2")
	assert_true(b.unregister_player("u1"))
	assert_false(b.has_player("u1"))
	var emissions := _capture_emissions(b)
	b.on_enemy_killed(5, "u2")
	assert_eq(emissions.size(), 1, "only u2 remains in the fan-out")
	assert_eq(emissions[0][0], "u2")

func test_unregister_player_unknown_id_noop():
	var b := XPBroadcaster.new()
	assert_false(b.unregister_player("nope"))

# --- EnemyStateSyncManager.apply_death --------------------------------------

func test_apply_death_removes_enemy_from_registry():
	# Issue scenario 4: apply_death removes the enemy from the local
	# enemy registry regardless of which client initiated the kill.
	var esm := EnemyStateSyncManager.new()
	esm.register_enemy("e1")
	esm.register_enemy("e2")
	assert_true(esm.is_alive("e1"))
	assert_true(esm.apply_death("e1"))
	assert_false(esm.is_alive("e1"))
	assert_true(esm.is_alive("e2"), "other enemies are unaffected")
	assert_eq(esm.alive_count(), 1)

func test_apply_death_idempotent_on_repeat():
	# A re-broadcast of the same death event (host's broadcast races a
	# local kill detection) doesn't error. Returns false the second
	# time so the caller can avoid double-awarding XP / loot.
	var esm := EnemyStateSyncManager.new()
	esm.register_enemy("e1")
	assert_true(esm.apply_death("e1"))
	assert_false(esm.apply_death("e1"), "second apply returns false")
	assert_eq(esm.alive_count(), 0)

func test_apply_death_unknown_id_returns_false():
	var esm := EnemyStateSyncManager.new()
	assert_false(esm.apply_death("ghost"))

func test_register_enemy_increments_count():
	var esm := EnemyStateSyncManager.new()
	assert_true(esm.register_enemy("e1"))
	assert_eq(esm.alive_count(), 1)
	assert_true(esm.is_alive("e1"))

func test_register_enemy_duplicate_rejected():
	# Idempotent on duplicate so a re-broadcast of the spawn event from
	# a flaky network doesn't double-count.
	var esm := EnemyStateSyncManager.new()
	esm.register_enemy("e1")
	assert_false(esm.register_enemy("e1"))
	assert_eq(esm.alive_count(), 1)

func test_register_enemy_empty_id_rejected():
	var esm := EnemyStateSyncManager.new()
	assert_false(esm.register_enemy(""))
	assert_eq(esm.alive_count(), 0)

func test_clear_drops_all_enemies():
	var esm := EnemyStateSyncManager.new()
	esm.register_enemy("e1")
	esm.register_enemy("e2")
	esm.clear()
	assert_eq(esm.alive_count(), 0)
	assert_false(esm.is_alive("e1"))

# --- RunXPSummary -----------------------------------------------------------

func test_run_xp_summary_accumulates_per_player():
	# AC #5: end-of-run screen shows XP earned by each player. The tally
	# subscribes to xp_awarded and accumulates per recipient — this is the
	# data the summary screen renders one row per player_id.
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	bc.register_player("p2")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(10)
	bc.on_enemy_killed(25)
	assert_eq(summary.total_for("p1"), 35)
	assert_eq(summary.total_for("p2"), 35)

func test_run_xp_summary_grand_total_sums_all_players():
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	bc.register_player("p2")
	bc.register_player("p3")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(50)
	# Three players each got 50 XP from the broadcast → 150 total.
	assert_eq(summary.grand_total(), 150)
	assert_eq(summary.player_count(), 3)

func test_run_xp_summary_independent_per_player():
	# Manually-fired emits routed to different ids accumulate separately.
	# (XPBroadcaster.on_enemy_killed fans out uniformly; this test pins
	# the tally's per-id isolation when a future caller hand-emits
	# non-uniform amounts, e.g. a host-only "killing blow bonus".)
	var bc := XPBroadcaster.new()
	var summary := RunXPSummary.new(bc)
	bc.xp_awarded.emit("p1", 10)
	bc.xp_awarded.emit("p2", 20)
	bc.xp_awarded.emit("p1", 5)
	assert_eq(summary.total_for("p1"), 15)
	assert_eq(summary.total_for("p2"), 20)
	assert_eq(summary.grand_total(), 35)

func test_run_xp_summary_total_for_unknown_id_returns_zero():
	# A row for a player who hasn't earned any XP yet shows 0, not a
	# crash. Lets the UI render every roster id even if a player AFK'd
	# the whole run.
	var summary := RunXPSummary.new()
	assert_eq(summary.total_for("ghost"), 0)
	assert_eq(summary.grand_total(), 0)
	assert_eq(summary.player_count(), 0)

func test_run_xp_summary_bind_is_idempotent():
	# Re-binding the same broadcaster doesn't double-subscribe (which
	# would double-count every event).
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	var summary := RunXPSummary.new()
	assert_true(summary.bind(bc), "first bind connects")
	assert_false(summary.bind(bc), "second bind rejected")
	bc.on_enemy_killed(10)
	assert_eq(summary.total_for("p1"), 10, "still only counts once")

func test_run_xp_summary_bind_null_returns_false():
	var summary := RunXPSummary.new()
	assert_false(summary.bind(null))

func test_run_xp_summary_unbind_stops_accumulation():
	# After unbind, future broadcasts do not accumulate. Lets the caller
	# freeze the tally before the next run starts (or before re-binding
	# to a fresh broadcaster).
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(10)
	assert_eq(summary.total_for("p1"), 10)
	assert_true(summary.unbind(bc))
	bc.on_enemy_killed(99)
	assert_eq(summary.total_for("p1"), 10, "post-unbind broadcast ignored")

func test_run_xp_summary_unbind_idempotent_when_not_bound():
	var bc := XPBroadcaster.new()
	var summary := RunXPSummary.new()
	assert_false(summary.unbind(bc), "not bound -> false")
	assert_false(summary.unbind(null), "null -> false")

func test_run_xp_summary_zero_or_negative_amount_no_op():
	# Defense-in-depth: broadcaster filters non-positive, but a hand-
	# fired emit (test harness, future debuff path) could route a 0 or
	# negative through. Don't pollute player_ids() with zero-tally rows.
	var bc := XPBroadcaster.new()
	var summary := RunXPSummary.new(bc)
	bc.xp_awarded.emit("p1", 0)
	bc.xp_awarded.emit("p1", -5)
	assert_eq(summary.total_for("p1"), 0)
	assert_eq(summary.player_count(), 0, "no row created for zero/negative")

func test_run_xp_summary_empty_player_id_no_op():
	# An empty player_id can't be a real party member. Reject so a
	# malformed wire payload doesn't pollute the tally with a "" row.
	var bc := XPBroadcaster.new()
	var summary := RunXPSummary.new(bc)
	bc.xp_awarded.emit("", 50)
	assert_eq(summary.player_count(), 0)
	assert_eq(summary.grand_total(), 0)

func test_run_xp_summary_to_dict_returns_copy():
	# Mutating the dict the caller got back must not corrupt the
	# internal tally. Same defensive shape as LobbyState.to_dict.
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(10)
	var snapshot := summary.to_dict()
	snapshot["p1"] = 9999
	snapshot["injected"] = 42
	assert_eq(summary.total_for("p1"), 10, "snapshot mutation didn't bleed in")
	assert_false(summary.to_dict().has("injected"))

func test_run_xp_summary_clear_resets_totals_but_keeps_binding():
	# Between runs, the orchestrator clears the per-run tally. The
	# binding stays (no need to re-subscribe), so the next run's
	# broadcasts accumulate fresh from zero.
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(10)
	summary.clear()
	assert_eq(summary.total_for("p1"), 0)
	assert_eq(summary.player_count(), 0)
	bc.on_enemy_killed(7)
	assert_eq(summary.total_for("p1"), 7, "binding survived clear")

func test_run_xp_summary_init_without_broadcaster_starts_empty():
	# A summary can be constructed without a broadcaster (e.g. when
	# the orchestrator wants to bind later, after the lobby fans out
	# the broadcaster instance). It just starts empty.
	var summary := RunXPSummary.new()
	assert_eq(summary.grand_total(), 0)
	assert_eq(summary.player_count(), 0)
	assert_eq(summary.player_ids(), [])

func test_run_xp_summary_end_to_end_three_player_run():
	# Full-run shape: register party, take three kills of varying
	# xp_reward, end-of-run screen reads per-player totals.
	var bc := XPBroadcaster.new()
	bc.register_player("alice")
	bc.register_player("bob")
	bc.register_player("carol")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(5)   # rat
	bc.on_enemy_killed(8)   # wraith
	bc.on_enemy_killed(20)  # boss
	assert_eq(summary.total_for("alice"), 33)
	assert_eq(summary.total_for("bob"), 33)
	assert_eq(summary.total_for("carol"), 33)
	assert_eq(summary.grand_total(), 99)
	assert_eq(summary.player_count(), 3)
