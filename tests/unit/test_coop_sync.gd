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

# --- RemotePlayerInterpolator.get_display_position_at ----------------------

func test_get_display_position_at_no_samples_returns_zero():
	# Wall-clock path mirrors get_display_position's no-sample contract —
	# returns ZERO so the remote kitten doesn't render at a stale origin
	# from a recycled interpolator.
	var ri := RemotePlayerInterpolator.new()
	assert_eq(ri.get_display_position_at(5.0), Vector2.ZERO)

func test_get_display_position_at_single_sample_returns_current():
	# After one sample there's no window to lerp across — returns
	# current_position regardless of `now`.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(10, 20), 1.0)
	assert_eq(ri.get_display_position_at(0.0), Vector2(10, 20))
	assert_eq(ri.get_display_position_at(1.0), Vector2(10, 20))
	assert_eq(ri.get_display_position_at(99.0), Vector2(10, 20))

func test_get_display_position_at_lerps_to_now():
	# Core path: two samples bracket `now`, the helper computes
	# t = (now - prev_ts) / (curr_ts - prev_ts) internally and lerps.
	# Pins that the wire layer / render loop doesn't have to compute t
	# inline.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 2.0)
	assert_eq(ri.get_display_position_at(1.5), Vector2(50, 0), "midpoint")
	assert_eq(ri.get_display_position_at(1.25), Vector2(25, 0), "quarter")
	assert_eq(ri.get_display_position_at(1.75), Vector2(75, 0), "three-quarter")

func test_get_display_position_at_now_equals_prev_ts_returns_previous():
	# Edge of the window: now == prev_ts -> t == 0 -> previous_position.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 2.0)
	assert_eq(ri.get_display_position_at(1.0), Vector2(0, 0))

func test_get_display_position_at_now_equals_curr_ts_returns_current():
	# Edge of the window: now == curr_ts -> t == 1 -> current_position.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 2.0)
	assert_eq(ri.get_display_position_at(2.0), Vector2(100, 0))

func test_get_display_position_at_now_before_prev_ts_clamps_to_previous():
	# Render loop clock skew: render is behind the wire layer's prev_ts.
	# t < 0 clamps via get_display_position to previous_position. The
	# kitten doesn't snap backwards past previous; it rests there until
	# the render clock catches up.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 2.0)
	assert_eq(ri.get_display_position_at(0.5), Vector2(0, 0))
	assert_eq(ri.get_display_position_at(-100.0), Vector2(0, 0))

func test_get_display_position_at_now_after_curr_ts_clamps_to_current():
	# Render loop ahead of the latest packet: t > 1 clamps via
	# get_display_position to current_position. The kitten freezes at
	# the latest known position rather than extrapolating off-screen
	# while waiting for the next packet to arrive.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 2.0)
	assert_eq(ri.get_display_position_at(2.5), Vector2(100, 0))
	assert_eq(ri.get_display_position_at(999.0), Vector2(100, 0))

func test_get_display_position_at_zero_window_returns_current():
	# Defensive against div-by-zero when both samples land in the same
	# tick (curr_ts == prev_ts). Returns current_position — the freshest
	# sample is the right answer; computing t would divide by zero.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 1.0)
	ri.push_sample(Vector2(100, 0), 1.0)  # same timestamp
	assert_eq(ri.get_display_position_at(1.0), Vector2(100, 0))
	assert_eq(ri.get_display_position_at(99.0), Vector2(100, 0), "regardless of now")

func test_get_display_position_at_backwards_time_returns_current():
	# Defensive against out-of-order wire-layer timestamps (curr_ts <
	# prev_ts — the manager didn't reorder a late-arriving packet).
	# Same "trust freshest" fallback as the zero-window case rather
	# than computing a negative-denominator t that would clamp
	# unpredictably.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(0, 0), 5.0)
	ri.push_sample(Vector2(100, 0), 2.0)  # timestamp went backwards
	assert_eq(ri.get_display_position_at(3.5), Vector2(100, 0))

func test_get_display_position_at_lerp_is_componentwise():
	# Confirms get_display_position_at routes through the same Vector2.lerp
	# as get_display_position — both axes interpolate, not just x.
	var ri := RemotePlayerInterpolator.new()
	ri.push_sample(Vector2(10, 20), 1.0)
	ri.push_sample(Vector2(30, 60), 2.0)
	assert_eq(ri.get_display_position_at(1.5), Vector2(20, 40))

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

# --- NetworkSyncManager.get_display_position_at ----------------------------

func test_nsm_get_display_position_at_unknown_player_returns_zero():
	# Mirrors get_display_position's unknown-id contract: a wire packet
	# for a player who already left the lobby returns ZERO rather than
	# crashing the render path.
	var nsm := NetworkSyncManager.new()
	assert_eq(nsm.get_display_position_at("ghost", 1.0), Vector2.ZERO)

func test_nsm_get_display_position_at_forwards_to_interpolator():
	# Two samples with a known window — manager forwards `now` through
	# to the interpolator's get_display_position_at, which lerps. Pins
	# that the manager doesn't accidentally pass `now` through to the
	# t-based variant.
	var nsm := NetworkSyncManager.new()
	nsm.apply_remote_state("u2", Vector2(0, 0), 1.0)
	nsm.apply_remote_state("u2", Vector2(100, 0), 2.0)
	assert_eq(nsm.get_display_position_at("u2", 1.5), Vector2(50, 0))
	assert_eq(nsm.get_display_position_at("u2", 1.25), Vector2(25, 0))

func test_nsm_get_display_position_at_per_player_isolation():
	# Two remote players bracket different windows — fetching one
	# doesn't perturb the other. Pins per-player interpolator isolation
	# through the wall-clock path too.
	var nsm := NetworkSyncManager.new()
	nsm.apply_remote_state("u2", Vector2(0, 0), 1.0)
	nsm.apply_remote_state("u2", Vector2(100, 0), 2.0)
	nsm.apply_remote_state("u3", Vector2(0, 0), 10.0)
	nsm.apply_remote_state("u3", Vector2(50, 0), 20.0)
	assert_eq(nsm.get_display_position_at("u2", 1.5), Vector2(50, 0))
	assert_eq(nsm.get_display_position_at("u3", 15.0), Vector2(25, 0))

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

# --- LocalXPRouter ----------------------------------------------------------

func _make_member(klass: int = CharacterData.CharacterClass.MAGE, lvl: int = 1) -> PartyMember:
	var c := CharacterData.make_new(klass, "k")
	c.level = lvl
	c.xp = 0
	c.max_hp = CharacterData.base_max_hp_for(klass, lvl)
	c.hp = c.max_hp
	return PartyMember.from_character(c)

func test_local_xp_router_routes_local_pid_to_member_real_stats():
	# Core wiring: an xp_awarded(local_pid, amount) emission lands on
	# the bound member's real_stats via XPSystem.award. Pins the
	# "kill-by-anyone awards XP to me" loop on the receiving end.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 1)
	var router := LocalXPRouter.new(bc, "me", member)
	assert_true(router.is_bound())
	bc.on_enemy_killed(3)  # under L1 threshold (5) — no level-up yet
	assert_eq(member.real_stats.xp, 3, "XP applied to real_stats")
	assert_eq(member.real_stats.level, 1)

func test_local_xp_router_filters_non_local_pid():
	# A broadcast for a different player's pid (the network bridge
	# fanning out a remote member's emission) does NOT mutate this
	# client's local member. Each client has its own router.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	bc.register_player("other")
	var member := _make_member()
	var _r := LocalXPRouter.new(bc, "me", member)
	# Hand-fire to the "other" id only; broadcaster.on_enemy_killed
	# would also fire to "me", which we don't want for this test.
	bc.xp_awarded.emit("other", 100)
	assert_eq(member.real_stats.xp, 0, "non-local-pid emission ignored")

func test_local_xp_router_levels_up_local_member_when_threshold_crossed():
	# Round-trip through XPSystem + ProgressionSystem: a kill awarding
	# enough XP to cross the L1->L2 boundary advances real_stats.level.
	# Pins that the router uses XPSystem.award (which calls add_xp) and
	# not a raw xp += amount that would skip level-up.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 1)
	var _r := LocalXPRouter.new(bc, "me", member)
	bc.on_enemy_killed(5)  # exactly L1->L2 threshold
	assert_eq(member.real_stats.level, 2, "level up applied")

func test_local_xp_router_applies_to_real_stats_not_effective_in_scaled_party():
	# AC #18#3: XP earned during a scaled session applies to real_stats
	# (the persistent character), not effective_stats (the in-game scaled
	# view). Pins use_real_level=true at the routing seam — without this,
	# a level-10 player scaled to floor 3 would keep their effective_stats
	# stuck at 3 forever without progress.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 10)
	member.apply_scaling(3)
	var pre_real_xp := member.real_stats.xp
	var pre_effective_xp := member.effective_stats.xp
	var _r := LocalXPRouter.new(bc, "me", member)
	bc.on_enemy_killed(3)
	assert_eq(member.real_stats.xp, pre_real_xp + 3, "real_stats.xp advanced")
	assert_eq(member.effective_stats.xp, pre_effective_xp, "effective_stats untouched")

func test_local_xp_router_bind_is_idempotent_on_same_broadcaster():
	# Re-binding the same broadcaster doesn't double-subscribe — without
	# this guard a re-bind during a session reset would double-apply XP
	# on every emission.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member()
	var router := LocalXPRouter.new()
	assert_true(router.bind(bc, "me", member), "first bind connects")
	assert_false(router.bind(bc, "me", member), "second bind to same bc rejected")
	bc.on_enemy_killed(3)
	assert_eq(member.real_stats.xp, 3, "still only routed once")

func test_local_xp_router_bind_to_different_broadcaster_unbinds_old():
	# Re-binding to a *different* broadcaster transparently drops the
	# old subscription. Lets the orchestrator reuse a router instance
	# across runs without forcing the caller to remember unbind().
	var bc1 := XPBroadcaster.new()
	bc1.register_player("me")
	var bc2 := XPBroadcaster.new()
	bc2.register_player("me")
	var member := _make_member()
	var router := LocalXPRouter.new(bc1, "me", member)
	assert_true(router.bind(bc2, "me", member), "rebind to bc2 succeeds")
	bc1.on_enemy_killed(50)
	assert_eq(member.real_stats.xp, 0, "old broadcaster no longer routes")
	bc2.on_enemy_killed(3)
	assert_eq(member.real_stats.xp, 3, "new broadcaster routes")

func test_local_xp_router_bind_rejects_null_broadcaster():
	var router := LocalXPRouter.new()
	assert_false(router.bind(null, "me", _make_member()))
	assert_false(router.is_bound())

func test_local_xp_router_bind_rejects_empty_player_id():
	# An empty local_player_id can't filter — every emission would either
	# match (empty pid is the default) or never match. Either is wrong.
	# Reject at bind so the caller surfaces the bad wire-up.
	var bc := XPBroadcaster.new()
	var router := LocalXPRouter.new()
	assert_false(router.bind(bc, "", _make_member()))
	assert_false(router.is_bound())

func test_local_xp_router_bind_rejects_null_member():
	# Without a member there's no real_stats to route to. Reject so the
	# caller doesn't end up with an "active" router that silently drops
	# every event.
	var bc := XPBroadcaster.new()
	var router := LocalXPRouter.new()
	assert_false(router.bind(bc, "me", null))
	assert_false(router.is_bound())

func test_local_xp_router_unbind_stops_routing():
	# After unbind, future broadcasts do not mutate the previously-bound
	# member. Lets the orchestrator hard-stop routing on session end.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member()
	var router := LocalXPRouter.new(bc, "me", member)
	bc.on_enemy_killed(3)
	assert_eq(member.real_stats.xp, 3)
	assert_true(router.unbind())
	assert_false(router.is_bound())
	bc.on_enemy_killed(99)
	assert_eq(member.real_stats.xp, 3, "post-unbind broadcast ignored")

func test_local_xp_router_unbind_idempotent_when_not_bound():
	var router := LocalXPRouter.new()
	assert_false(router.unbind(), "no-op returns false")

func test_local_xp_router_init_without_args_starts_unbound():
	# Default-constructed router (test / pre-handshake) is inert. Apps
	# that don't yet have a broadcaster + local id can hold a reference
	# without it firing.
	var router := LocalXPRouter.new()
	assert_false(router.is_bound())
	assert_eq(router.local_player_id, "")
	assert_null(router.local_member)

func test_local_xp_router_filters_emission_to_other_in_full_broadcast():
	# Full broadcast shape: bc has 3 registered players, on_enemy_killed
	# fires once per player, but only the local-pid emission lands on
	# the local member's stats. The other two emissions are intended
	# for the other clients' routers and must not bleed in here.
	var bc := XPBroadcaster.new()
	bc.register_player("alice")
	bc.register_player("bob")
	bc.register_player("carol")
	var alice := _make_member()
	var _r := LocalXPRouter.new(bc, "alice", alice)
	bc.on_enemy_killed(3)  # broadcast fires xp_awarded for all three
	# Only the alice emission landed on alice's real_stats — not 3x amount.
	assert_eq(alice.real_stats.xp, 3, "XP applied exactly once, not per-fanout")

# --- LocalXPRouter.level_up signal ------------------------------------------

func test_local_xp_router_emits_level_up_when_threshold_crossed():
	# An XP award that crosses a level threshold emits level_up(old, new).
	# Subscribers (LocalTokenGrantRouter, future "level-up VFX") use this
	# instead of polling member.real_stats.level.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 1)
	var router := LocalXPRouter.new(bc, "me", member)
	var events: Array = []
	router.level_up.connect(func(old_l, new_l): events.append([old_l, new_l]))
	bc.on_enemy_killed(5)  # exactly L1->L2 threshold
	assert_eq(events.size(), 1, "single level-up emits once")
	assert_eq(events[0], [1, 2], "old + new levels reported")

func test_local_xp_router_no_level_up_emit_when_xp_below_threshold():
	# XP gain that doesn't cross a level boundary must NOT emit level_up.
	# Subscribers should only react to actual level transitions; emitting
	# on every XP gain would spam token grants for non-milestone events.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 1)
	var router := LocalXPRouter.new(bc, "me", member)
	var emitted := [false]
	router.level_up.connect(func(_o, _n): emitted[0] = true)
	bc.on_enemy_killed(3)  # under L1->L2 threshold (5)
	assert_false(emitted[0], "no level transition => no level_up emit")

func test_local_xp_router_emits_single_level_up_for_multi_level_dump():
	# A massive XP dump that crosses several levels emits ONE level_up
	# with the full (old, new) range. Single emission keeps the
	# subscriber rule (TokenGrantRules.tokens_for_level_up) responsible
	# for counting milestones in the open-closed range — the router
	# doesn't have to slice the dump per-level.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 1)
	var router := LocalXPRouter.new(bc, "me", member)
	var events: Array = []
	router.level_up.connect(func(o, n): events.append([o, n]))
	bc.on_enemy_killed(10000)  # force several levels in one shot
	assert_eq(events.size(), 1, "one emission per XP application")
	assert_eq(events[0][0], 1, "old level captured pre-application")
	assert_gt(events[0][1], 1, "new level reflects post-application")

func test_local_xp_router_does_not_emit_level_up_for_non_local_pid():
	# A broadcast for a remote pid is filtered out before the level
	# transition is checked, so level_up never fires for remote XP.
	# Pins that the local-pid filter sits before the level read.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	bc.register_player("other")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 1)
	var router := LocalXPRouter.new(bc, "me", member)
	var emitted := [false]
	router.level_up.connect(func(_o, _n): emitted[0] = true)
	bc.xp_awarded.emit("other", 10000)  # would-be level dump for remote
	assert_false(emitted[0], "remote-pid emission ignored by level_up too")

# --- LocalTokenGrantRouter --------------------------------------------------

func _make_router(member: PartyMember) -> LocalXPRouter:
	# Bound LocalXPRouter for use as a level_up source. Tests trigger
	# level_up by either firing through the broadcaster or hand-emitting.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	return LocalXPRouter.new(bc, "me", member)

func test_local_token_router_grants_milestone_token_on_level_up():
	# Core wiring: a level_up that crosses a milestone (L4->L5) emits
	# one token to the inventory. Closes the "remote-killer XP that
	# crosses my milestone level still drips a token" loop on the
	# receiving end.
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router := _make_router(member)
	var inv := TokenInventory.new()
	var token_router := LocalTokenGrantRouter.new(router, inv)
	assert_true(token_router.is_bound())
	router.level_up.emit(4, 5)
	assert_eq(inv.count, TokenGrantRules.tokens_for_level_up(4, 5),
		"milestone L5 grants exactly one token")
	assert_eq(token_router.granted_total, inv.count,
		"granted_total mirrors the count delta")

func test_local_token_router_no_grant_when_no_milestone_crossed():
	# L2->L3 crosses no multiple-of-5 — no tokens granted. Pins that
	# the router doesn't drip tokens on every level-up, only milestones.
	var member := _make_member(CharacterData.CharacterClass.MAGE, 2)
	var router := _make_router(member)
	var inv := TokenInventory.new()
	var token_router := LocalTokenGrantRouter.new(router, inv)
	router.level_up.emit(2, 3)
	assert_eq(inv.count, 0, "non-milestone level-up grants zero tokens")
	assert_eq(token_router.granted_total, 0)

func test_local_token_router_grants_multiple_for_multi_milestone_dump():
	# A massive XP dump that spans L4->L11 crosses both L5 and L10 —
	# two tokens. Pins that the rule's open-closed range handles the
	# multi-milestone case correctly through the router.
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router := _make_router(member)
	var inv := TokenInventory.new()
	var token_router := LocalTokenGrantRouter.new(router, inv)
	router.level_up.emit(4, 11)
	assert_eq(inv.count, 2, "L4->L11 crossed two milestones")
	assert_eq(token_router.granted_total, 2)

func test_local_token_router_end_to_end_via_broadcast():
	# Full shape: kill broadcast through XPBroadcaster lands on the local
	# member, level transitions to L5, milestone token drips. Pins that
	# the wire actually propagates from broadcast all the way to inventory.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router := LocalXPRouter.new(bc, "me", member)
	var inv := TokenInventory.new()
	var _t := LocalTokenGrantRouter.new(router, inv)
	# xp_to_next_level(4) = 5 + 3*5 = 20
	bc.on_enemy_killed(ProgressionSystem.xp_to_next_level(4))
	assert_eq(member.real_stats.level, 5, "member leveled up")
	assert_eq(inv.count, 1, "milestone token granted via broadcast pipe")

func test_local_token_router_filters_remote_pid_via_xp_router():
	# A remote-pid broadcast doesn't level the local member, so no token
	# drips. The filter is enforced upstream in LocalXPRouter — this test
	# pins that the token router inherits the filter without re-checking.
	var bc := XPBroadcaster.new()
	bc.register_player("me")
	bc.register_player("other")
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router := LocalXPRouter.new(bc, "me", member)
	var inv := TokenInventory.new()
	var _t := LocalTokenGrantRouter.new(router, inv)
	bc.xp_awarded.emit("other", 10000)  # would level "other" if local
	assert_eq(inv.count, 0, "remote-pid broadcast doesn't grant local tokens")

func test_local_token_router_bind_idempotent_on_same_router():
	# Re-binding the same router doesn't double-subscribe — without this
	# guard a re-bind during a session reset would double-grant on every
	# milestone.
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router := _make_router(member)
	var inv := TokenInventory.new()
	var token_router := LocalTokenGrantRouter.new()
	assert_true(token_router.bind(router, inv), "first bind connects")
	assert_false(token_router.bind(router, inv), "second bind to same router rejected")
	router.level_up.emit(4, 5)
	assert_eq(inv.count, 1, "single grant despite double-bind attempt")

func test_local_token_router_bind_to_different_router_unbinds_old():
	# Re-binding to a *different* router transparently drops the old
	# subscription. Lets the orchestrator reuse the token-router instance
	# across runs without forcing the caller to remember unbind().
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router1 := _make_router(member)
	var router2 := _make_router(member)
	var inv := TokenInventory.new()
	var token_router := LocalTokenGrantRouter.new(router1, inv)
	assert_true(token_router.bind(router2, inv), "rebind to router2 succeeds")
	router1.level_up.emit(4, 5)
	assert_eq(inv.count, 0, "old router no longer routes")
	router2.level_up.emit(4, 5)
	assert_eq(inv.count, 1, "new router routes")

func test_local_token_router_bind_rejects_null_router():
	var token_router := LocalTokenGrantRouter.new()
	assert_false(token_router.bind(null, TokenInventory.new()))
	assert_false(token_router.is_bound())

func test_local_token_router_bind_rejects_null_inventory():
	# Without an inventory there's nothing to grant to. Reject so the
	# caller doesn't end up with a "bound" router that silently no-ops.
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router := _make_router(member)
	var token_router := LocalTokenGrantRouter.new()
	assert_false(token_router.bind(router, null))
	assert_false(token_router.is_bound())

func test_local_token_router_unbind_stops_grants():
	# After unbind, future level-ups don't grant tokens. Lets the
	# orchestrator hard-stop grants on session end.
	var member := _make_member(CharacterData.CharacterClass.MAGE, 4)
	var router := _make_router(member)
	var inv := TokenInventory.new()
	var token_router := LocalTokenGrantRouter.new(router, inv)
	router.level_up.emit(4, 5)
	assert_eq(inv.count, 1)
	assert_true(token_router.unbind())
	assert_false(token_router.is_bound())
	router.level_up.emit(5, 10)  # would-be second milestone
	assert_eq(inv.count, 1, "post-unbind level-up ignored")

func test_local_token_router_unbind_idempotent_when_not_bound():
	var token_router := LocalTokenGrantRouter.new()
	assert_false(token_router.unbind(), "no-op returns false")

func test_local_token_router_init_without_args_starts_unbound():
	# Default-constructed router (test / pre-handshake) is inert.
	var token_router := LocalTokenGrantRouter.new()
	assert_false(token_router.is_bound())
	assert_eq(token_router.granted_total, 0)

# --- DungeonSeedSync --------------------------------------------------------

func test_seed_sync_starts_unagreed():
	# A fresh sync has no agreed seed. is_agreed gates the wire layer's
	# "ready to broadcast generate(seed)" check — without it, the host's
	# scene-tree dungeon would try to generate before host_mint ran.
	var sync := DungeonSeedSync.new()
	assert_false(sync.is_agreed())
	assert_eq(sync.current_seed(), DungeonSeedSync.NOT_AGREED)
	assert_eq(DungeonSeedSync.NOT_AGREED, -1, "sentinel matches DungeonGenerator's randomize sentinel")

func test_host_mint_produces_non_negative_seed():
	# The randomize path must never mint NOT_AGREED (-1). A negative
	# seed would route through DungeonGenerator's `seed < 0 → randomize`
	# branch, defeating the point of agreeing on a seed.
	var sync := DungeonSeedSync.new()
	var s := sync.host_mint()
	assert_true(s >= 0, "minted seed must be non-negative")
	assert_true(sync.is_agreed())
	assert_eq(sync.current_seed(), s)

func test_host_mint_emits_seed_agreed():
	# The signal lets the wire layer / orchestrator react to the
	# agreement without polling is_agreed each frame.
	var sync := DungeonSeedSync.new()
	watch_signals(sync)
	var s := sync.host_mint(42)
	assert_signal_emitted_with_parameters(sync, "seed_agreed", [s])
	assert_signal_emit_count(sync, "seed_agreed", 1)

func test_host_mint_idempotent_returns_existing_seed():
	# Re-mint after the broadcast has gone out would desync remote
	# clients (they already received the first seed). Idempotent return
	# keeps a host UI's double-fired "start match" safe.
	var sync := DungeonSeedSync.new()
	var first := sync.host_mint(1234)
	var second := sync.host_mint(9999)
	assert_eq(second, first, "second host_mint returns the original seed")
	assert_eq(sync.current_seed(), 1234, "override on second call is ignored")

func test_host_mint_idempotent_does_not_re_emit_signal():
	# A second seed_agreed emission would lie — the seed didn't change.
	var sync := DungeonSeedSync.new()
	watch_signals(sync)
	sync.host_mint(7)
	sync.host_mint(7)
	assert_signal_emit_count(sync, "seed_agreed", 1, "second host_mint is silent")

func test_host_mint_with_override_uses_override():
	# Deterministic seed for tests / "replay this dungeon" QA path.
	var sync := DungeonSeedSync.new()
	assert_eq(sync.host_mint(12345), 12345)
	assert_eq(sync.current_seed(), 12345)

func test_host_mint_random_path_produces_different_seeds_across_instances():
	# Two un-overridden mints across separate instances should diverge
	# (otherwise every match would generate the same dungeon). Not a
	# strict guarantee — randomize() COULD coincidentally collide — so
	# we draw a few and assert at-least-one-differs to keep the test
	# stable. Accepts a tiny flake probability (~1 in 2^31 per pair) as
	# the cost of pinning the contract.
	var seeds: Array[int] = []
	for _i in range(5):
		var s := DungeonSeedSync.new()
		seeds.append(s.host_mint())
	var any_differ := false
	for i in range(seeds.size() - 1):
		if seeds[i] != seeds[i + 1]:
			any_differ = true
			break
	assert_true(any_differ, "random mints should produce at least one differing pair across 5 instances")

func test_apply_remote_seed_stores_seed():
	var sync := DungeonSeedSync.new()
	assert_true(sync.apply_remote_seed(98765))
	assert_true(sync.is_agreed())
	assert_eq(sync.current_seed(), 98765)

func test_apply_remote_seed_zero_accepted():
	# Zero is a valid deterministic seed (DungeonGenerator treats it as
	# such; only seed < 0 means randomize). The NOT_AGREED sentinel is
	# -1, not 0, so apply_remote_seed(0) must succeed.
	var sync := DungeonSeedSync.new()
	assert_true(sync.apply_remote_seed(0))
	assert_eq(sync.current_seed(), 0)
	assert_true(sync.is_agreed())

func test_apply_remote_seed_emits_seed_agreed():
	var sync := DungeonSeedSync.new()
	watch_signals(sync)
	sync.apply_remote_seed(555)
	assert_signal_emitted_with_parameters(sync, "seed_agreed", [555])
	assert_signal_emit_count(sync, "seed_agreed", 1)

func test_apply_remote_seed_negative_rejected():
	# Defensive against wire-payload corruption that flips a sign bit.
	# A negative seed would otherwise route through DungeonGenerator's
	# randomize branch, silently desyncing this client from the host.
	var sync := DungeonSeedSync.new()
	assert_false(sync.apply_remote_seed(-1))
	assert_false(sync.apply_remote_seed(-42))
	assert_false(sync.is_agreed())
	assert_eq(sync.current_seed(), DungeonSeedSync.NOT_AGREED)

func test_apply_remote_seed_already_agreed_rejected():
	# Re-broadcast from a flaky network is a no-op rather than an
	# overwrite. An overwrite would mid-match swap the dungeon layout
	# under the player's feet.
	var sync := DungeonSeedSync.new()
	sync.apply_remote_seed(100)
	assert_false(sync.apply_remote_seed(200))
	assert_eq(sync.current_seed(), 100, "second apply did not overwrite first")

func test_apply_remote_seed_after_host_mint_rejected():
	# Same idempotency rule across host/remote: if this instance is
	# already the host (it minted), a stray remote-seed packet doesn't
	# overwrite the host's authoritative pick.
	var sync := DungeonSeedSync.new()
	sync.host_mint(77)
	assert_false(sync.apply_remote_seed(88))
	assert_eq(sync.current_seed(), 77)

func test_host_mint_after_apply_remote_seed_rejected():
	# Symmetric: if this instance already received a remote seed (it's
	# the remote), a host_mint call returns the existing seed without
	# overwriting. Defends against a misclassified-role caller.
	var sync := DungeonSeedSync.new()
	sync.apply_remote_seed(42)
	assert_eq(sync.host_mint(), 42)
	assert_eq(sync.current_seed(), 42)

func test_seed_sync_reset_clears_state():
	# After reset, the sync is reusable for the next match. The future
	# match orchestrator calls reset() between runs ("play again" from
	# the summary screen) so it doesn't allocate a fresh sync per
	# match.
	var sync := DungeonSeedSync.new()
	sync.host_mint(123)
	assert_true(sync.is_agreed())
	sync.reset()
	assert_false(sync.is_agreed())
	assert_eq(sync.current_seed(), DungeonSeedSync.NOT_AGREED)
	# Fresh apply works after reset.
	assert_true(sync.apply_remote_seed(456))
	assert_eq(sync.current_seed(), 456)

func test_seed_sync_reset_allows_re_emit_of_seed_agreed():
	# After reset, the next agreement (mint or apply) emits seed_agreed
	# again — so a UI subscriber sees a fresh "match started" edge per
	# match.
	var sync := DungeonSeedSync.new()
	watch_signals(sync)
	sync.host_mint(1)
	sync.reset()
	sync.host_mint(2)
	assert_signal_emit_count(sync, "seed_agreed", 2)

func test_seed_sync_end_to_end_host_and_remote_converge_on_same_dungeon():
	# Issue #17 AC#1 ("2-4 players can crawl the same dungeon
	# simultaneously"). Pin that the host's mint and the remote's
	# apply, routed through DungeonGenerator.generate(seed), produce
	# identical room graphs. Without this contract, every client
	# would draw its own seed and the layouts would diverge.
	var host_sync := DungeonSeedSync.new()
	var remote_sync := DungeonSeedSync.new()
	var seed := host_sync.host_mint()
	assert_true(remote_sync.apply_remote_seed(seed))
	var host_dungeon := DungeonGenerator.generate(host_sync.current_seed())
	var remote_dungeon := DungeonGenerator.generate(remote_sync.current_seed())
	assert_eq(host_dungeon.rooms.size(), remote_dungeon.rooms.size(), "same room count")
	assert_eq(host_dungeon.boss_id, remote_dungeon.boss_id, "same boss id")
	assert_eq(host_dungeon.start_id, remote_dungeon.start_id, "same start id")
	for i in range(host_dungeon.rooms.size()):
		var hr: Room = host_dungeon.rooms[i]
		var rr: Room = remote_dungeon.rooms[i]
		assert_eq(hr.id, rr.id, "room %d: same id" % i)
		assert_eq(hr.type, rr.type, "room %d: same type" % i)
		assert_eq(hr.enemy_kind, rr.enemy_kind, "room %d: same enemy kind" % i)
		assert_eq(hr.power_up_type, rr.power_up_type, "room %d: same power-up type" % i)
		assert_eq(hr.connections, rr.connections, "room %d: same connections" % i)

# --- RemoteKillApplier ------------------------------------------------------

func _make_lobby_for_apply(player_specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
		ls.add_player(LobbyPlayer.make(spec[0], spec[1], spec[2], false))
	return ls

func _make_two_room_dungeon_for_apply() -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	d.add_room(start)
	d.start_id = 0
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.RAT
	d.add_room(boss)
	d.boss_id = 1
	return d

func _make_active_session_for_apply(local_id: String = "u1") -> CoopSession:
	# An active session bound to local_id with one party member. Pre-
	# registers a single enemy "e1" so the rising-edge tests have an id
	# to apply. Tests that need a missing id skip the register and call
	# apply with their own enemy_id.
	var lobby := _make_lobby_for_apply([["u1", "A", "Mage"]])
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.level = 1
	c.xp = 0
	var session := CoopSession.new(lobby, {"u1": c}, null, null, local_id)
	session.start(_make_two_room_dungeon_for_apply())
	session.enemy_sync.register_enemy("e1")
	return session

func test_remote_kill_apply_null_session_returns_false():
	# Pre-handshake / test path with no session at all. Must no-op
	# rather than crash so the wire-layer handler can be a single
	# unconditional call site.
	assert_false(RemoteKillApplier.apply(null, "e1", "u2", 5))

func test_remote_kill_apply_inactive_session_returns_false():
	# Constructed but not started — broadcaster + registry are both
	# null in that window so a remote packet has nothing to apply
	# against. Must no-op rather than crash on the null deref.
	var lobby := _make_lobby_for_apply([["u1", "A", "Mage"]])
	var session := CoopSession.new(lobby, {"u1": CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")}, null, null, "u1")
	assert_false(session.is_active())
	assert_false(RemoteKillApplier.apply(session, "e1", "u2", 5))

func test_remote_kill_apply_after_end_returns_false():
	# Post-end() session. Same shape as inactive — managers dropped.
	# A late-arriving wire packet for a session that already ended
	# must not crash on the dropped registry.
	var session := _make_active_session_for_apply("u1")
	session.end()
	assert_false(session.is_active())
	assert_false(RemoteKillApplier.apply(session, "e1", "u2", 5))

func test_remote_kill_apply_empty_enemy_id_returns_false():
	# Defensive: pre-spawn-layer / corrupted packet with no enemy_id.
	# Without a stable id we can't gate idempotency, so we skip the
	# broadcast to avoid double-XP on a re-broadcast. The wire layer
	# is responsible for never minting empty-id packets — this is
	# defense-in-depth.
	var session := _make_active_session_for_apply("u1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	assert_false(RemoteKillApplier.apply(session, "", "u2", 5))
	assert_eq(emissions.size(), 0, "no broadcast on empty enemy_id")
	assert_true(session.enemy_sync.is_alive("e1"), "registry untouched")

func test_remote_kill_apply_rising_edge_returns_true():
	# Core wiring: a fresh wire packet for a registered enemy returns
	# true (rising edge), removes the enemy from the registry, and
	# fires the local broadcaster so the LocalXPRouter applies the
	# XP to my member's real_stats.
	var session := _make_active_session_for_apply("u1")
	assert_true(session.enemy_sync.is_alive("e1"))
	var assigned := RemoteKillApplier.apply(session, "e1", "u2", 5)
	assert_true(assigned, "rising-edge apply returns true")
	assert_false(session.enemy_sync.is_alive("e1"), "registry erased")

func test_remote_kill_apply_fires_broadcaster():
	# The remote-side broadcast lands on every registered player's
	# xp_awarded emission. The local LocalXPRouter picks its own pid
	# and applies the amount; this test pins that the broadcaster
	# itself fired with the correct amount and killer.
	var session := _make_active_session_for_apply("u1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	RemoteKillApplier.apply(session, "e1", "u2", 7)
	assert_eq(emissions.size(), 1, "single-member party fires once")
	assert_eq(emissions[0][0], "u1", "fan-out targets registered pid, not killer_id")
	assert_eq(emissions[0][1], 7, "amount carried through unchanged")

func test_remote_kill_apply_fan_out_targets_all_party_members():
	# Pin the AC#3 loop on the receive side: a remote-killer kill
	# fires the local broadcaster which fans out to every registered
	# party member. The killer_id ("u2") is metadata; every registered
	# pid still gets an emission with the same amount.
	var lobby := _make_lobby_for_apply([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
		["u3", "C", "Thief"],
	])
	var c1 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var c2 := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "k")
	var c3 := CharacterData.make_new(CharacterData.CharacterClass.THIEF, "k")
	var session := CoopSession.new(lobby, {"u1": c1, "u2": c2, "u3": c3}, null, null, "u1")
	session.start(_make_two_room_dungeon_for_apply())
	session.enemy_sync.register_enemy("e1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	# u3 got the killing blow remotely; my client (u1) receives the packet.
	RemoteKillApplier.apply(session, "e1", "u3", 10)
	assert_eq(emissions.size(), 3, "fan-out hits all three party members")
	for e in emissions:
		assert_eq(e[1], 10, "every emission carries the same amount")

func test_remote_kill_apply_routes_xp_to_local_member_via_router():
	# Full receive-side shape: wire packet -> apply -> broadcast ->
	# LocalXPRouter (constructed by CoopSession.start with local_id="u1")
	# -> XPSystem.award -> member.real_stats. Pins that a remote-killer
	# kill ends up on this client's own CharacterData.xp.
	var session := _make_active_session_for_apply("u1")
	var local := session.member_for("u1")
	assert_eq(local.real_stats.xp, 0)
	RemoteKillApplier.apply(session, "e1", "u2", 4)  # killer is u2, NOT me
	assert_eq(local.real_stats.xp, 4, "XP applied to my real_stats via router")

func test_remote_kill_apply_idempotent_on_duplicate_packet():
	# A re-send from a flaky network arrives twice. apply_death's
	# idempotency means the second call returns false here, and
	# crucially the broadcast does NOT fire the second time. XP
	# applies exactly once per enemy.
	var session := _make_active_session_for_apply("u1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	assert_true(RemoteKillApplier.apply(session, "e1", "u2", 5))
	assert_false(RemoteKillApplier.apply(session, "e1", "u2", 5), "duplicate packet rejected")
	assert_eq(emissions.size(), 1, "broadcast fires exactly once across both calls")

func test_remote_kill_apply_unknown_enemy_id_returns_false():
	# Wire packet for an enemy we never registered (out-of-order: death
	# arrived before spawn, or a wire-layer bug). apply_death returns
	# false on the unknown erase; we don't broadcast either since we
	# can't distinguish "unknown" from "duplicate" without extra state,
	# and treating both the same keeps the contract narrow.
	var session := _make_active_session_for_apply("u1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	assert_false(RemoteKillApplier.apply(session, "ghost_e99", "u2", 5))
	assert_eq(emissions.size(), 0, "no broadcast for unknown enemy")
	assert_true(session.enemy_sync.is_alive("e1"), "registered enemy untouched")

func test_remote_kill_apply_does_not_double_fire_with_local_kill():
	# Convergence test: KillRewardRouter (local-side) and
	# RemoteKillApplier (receive-side) both gate through apply_death.
	# A local kill followed by a duplicate remote packet (host
	# echoing its own broadcast back to itself) does NOT double-apply
	# XP. Same idempotent registry guards both sides.
	var session := _make_active_session_for_apply("u1")
	var local := session.member_for("u1")
	var enemy_data := EnemyData.make_new(EnemyData.EnemyKind.RAT)
	enemy_data.enemy_id = "e1"
	enemy_data.xp_reward = 3
	# Local kill first: applies XP via LocalXPRouter (3) and erases e1.
	KillRewardRouter.route_kill(local.real_stats, enemy_data, null, session, "u1")
	assert_eq(local.real_stats.xp, 3, "local kill applied XP once")
	assert_false(session.enemy_sync.is_alive("e1"), "registry erased by local kill")
	# Now the same kill comes back as a wire echo. apply_death returns
	# false on the already-erased id; the broadcast does NOT fire again.
	assert_false(RemoteKillApplier.apply(session, "e1", "u1", 3))
	assert_eq(local.real_stats.xp, 3, "no double-XP from echoed packet")

func test_remote_kill_apply_zero_xp_still_erases():
	# A wire packet with xp_value=0 (e.g. a kill with no XP reward)
	# still counts as a rising-edge erase. The broadcaster's own
	# non-positive guard makes the broadcast a silent no-op. Returns
	# true so the caller drives the scene-tree side (queue_free the
	# enemy node).
	var session := _make_active_session_for_apply("u1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	assert_true(RemoteKillApplier.apply(session, "e1", "u2", 0))
	assert_false(session.enemy_sync.is_alive("e1"), "registry erased even with zero XP")
	assert_eq(emissions.size(), 0, "broadcaster's own guard suppresses zero-amount fan-out")

func test_remote_kill_apply_negative_xp_does_not_emit():
	# Defense-in-depth: a future debuff path / corrupted packet hands
	# us a negative xp. The broadcaster's non-positive guard suppresses
	# the fan-out, but the registry still erases (the kill happened —
	# the XP delta is the corrupted part).
	var session := _make_active_session_for_apply("u1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	assert_true(RemoteKillApplier.apply(session, "e1", "u2", -5))
	assert_false(session.enemy_sync.is_alive("e1"))
	assert_eq(emissions.size(), 0, "negative xp suppressed by broadcaster guard")

func test_remote_kill_apply_empty_killer_id_still_broadcasts():
	# killer_id is metadata only — the broadcaster fans out to every
	# registered pid regardless of who killed. An empty killer_id (a
	# wire-layer field that wasn't set, or an environmental death like
	# a lava hazard) doesn't gate the broadcast.
	var session := _make_active_session_for_apply("u1")
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	assert_true(RemoteKillApplier.apply(session, "e1", "", 6))
	assert_eq(emissions.size(), 1, "fan-out fires regardless of empty killer_id")
	assert_eq(emissions[0][1], 6)

func test_remote_kill_apply_levels_up_local_member_through_router():
	# End-to-end: a remote-killer kill arrives via wire, RemoteKillApplier
	# fires the broadcaster, LocalXPRouter applies the XP, and the local
	# member levels up. Closes the AC#3 loop end-to-end on the receiving
	# side: a kill by ANY player levels me up if I cross my threshold.
	# (xp_to_next_level(1) = 5, so 5 XP exactly crosses L1->L2.)
	var session := _make_active_session_for_apply("u1")
	var local := session.member_for("u1")
	assert_eq(local.real_stats.level, 1)
	RemoteKillApplier.apply(session, "e1", "u2", ProgressionSystem.xp_to_next_level(1))
	assert_eq(local.real_stats.level, 2, "remote-killer kill leveled local member up")

func test_remote_kill_apply_grants_milestone_token_when_local_crosses_milestone():
	# Crossing a milestone (L4 -> L5) via a remote-killer kill drips
	# a revive token to the local TokenInventory through the existing
	# LocalTokenGrantRouter. Pins that the wire-layer receive path
	# unlocks the same token-drip that a local kill would, since both
	# routes share the broadcaster -> LocalXPRouter.level_up edge.
	var lobby := _make_lobby_for_apply([["u1", "A", "Mage"]])
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.level = 4
	c.xp = 0
	var inv := TokenInventory.new()
	# Inventory injected so CoopSession.start wires LocalTokenGrantRouter.
	var session := CoopSession.new(lobby, {"u1": c}, null, inv, "u1")
	session.start(_make_two_room_dungeon_for_apply())
	session.enemy_sync.register_enemy("e1")
	# xp_to_next_level(4) = 5 + 3*5 = 20, exactly crosses L4->L5.
	RemoteKillApplier.apply(session, "e1", "u2", ProgressionSystem.xp_to_next_level(4))
	assert_eq(c.level, 5, "remote-killer kill leveled me to L5")
	assert_eq(inv.count, TokenGrantRules.tokens_for_level_up(4, 5),
		"milestone token drips through the same level_up pipe")

# --- RunSummaryRowBuilder ---------------------------------------------------

func _make_lobby_for_summary(player_specs: Array) -> LobbyState:
	# spec: [player_id, kitten_name, class_name, is_host]
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
		var host: bool = spec.size() > 3 and bool(spec[3])
		ls.add_player(LobbyPlayer.make(spec[0], spec[1], spec[2], host))
	return ls

func test_summary_rows_null_session_returns_empty():
	# Pre-handshake / test path with no session at all. UI's empty-state
	# placeholder branch fires when this returns []; must not crash on
	# the iterator.
	assert_eq(RunSummaryRowBuilder.build_rows(null), [])

func test_summary_rows_default_constructed_session_returns_empty():
	# Constructed without a lobby (default args) — no member ids, no
	# tally, nothing to render. UI's empty-state placeholder again.
	var session := CoopSession.new()
	assert_eq(RunSummaryRowBuilder.build_rows(session), [])

func test_summary_rows_from_summary_and_lobby_basic():
	# Two players, both earned XP. Rows render in the supplied order
	# with the join-with-lobby fields populated.
	var lobby := _make_lobby_for_summary([
		["u1", "Whiskers", "Mage", true],
		["u2", "Mittens", "Thief", false],
	])
	var bc := XPBroadcaster.new()
	bc.register_player("u1")
	bc.register_player("u2")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(15, "u1")
	bc.on_enemy_killed(10, "u2")
	# u1 + u2 each got 25 XP (15 + 10).
	var rows := RunSummaryRowBuilder.build_rows_from(summary, lobby, "u1", ["u1", "u2"])
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["player_id"], "u1")
	assert_eq(rows[0]["kitten_name"], "Whiskers")
	assert_eq(rows[0]["class_name"], "Mage")
	assert_eq(rows[0]["xp_earned"], 25)
	assert_true(rows[0]["is_local"])
	assert_true(rows[0]["is_host"])
	assert_eq(rows[1]["player_id"], "u2")
	assert_eq(rows[1]["kitten_name"], "Mittens")
	assert_eq(rows[1]["class_name"], "Thief")
	assert_eq(rows[1]["xp_earned"], 25)
	assert_false(rows[1]["is_local"])
	assert_false(rows[1]["is_host"])

func test_summary_rows_preserve_order_from_ordered_ids():
	# The ordered_player_ids array is the source of truth for row order.
	# Reverse the order and the rows reverse — pins that the join with
	# the lobby doesn't re-sort by lobby insertion order.
	var lobby := _make_lobby_for_summary([
		["u1", "A", "Mage"],
		["u2", "B", "Thief"],
		["u3", "C", "Ninja"],
	])
	var rows := RunSummaryRowBuilder.build_rows_from(null, lobby, "", ["u3", "u1", "u2"])
	assert_eq(rows.size(), 3)
	assert_eq(rows[0]["player_id"], "u3")
	assert_eq(rows[1]["player_id"], "u1")
	assert_eq(rows[2]["player_id"], "u2")

func test_summary_rows_zero_xp_player_still_renders():
	# A party member who got no kills (their tally is 0) still renders
	# a row — they were in the party, the summary screen needs to show
	# them with a +0 XP line, not silently drop them.
	var lobby := _make_lobby_for_summary([
		["u1", "A", "Mage"],
		["u2", "B", "Thief"],
	])
	var bc := XPBroadcaster.new()
	bc.register_player("u1")
	bc.register_player("u2")
	var summary := RunXPSummary.new(bc)
	# No emissions — u1 and u2 both have tally 0.
	var rows := RunSummaryRowBuilder.build_rows_from(summary, lobby, "", ["u1", "u2"])
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["xp_earned"], 0)
	assert_eq(rows[1]["xp_earned"], 0)

func test_summary_rows_player_in_summary_but_not_ordered_dropped():
	# A stale tally entry (player who left mid-match and was dropped
	# from the lobby roster + ordered_player_ids but not from the per-
	# run tally) does NOT render a ghost row. ordered_player_ids is
	# the source of truth for which rows render.
	var lobby := _make_lobby_for_summary([["u1", "A", "Mage"]])
	var bc := XPBroadcaster.new()
	bc.register_player("u1")
	bc.register_player("u_left")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(7, "u1")
	# u_left has a tally entry but isn't in the ordered ids -> dropped.
	var rows := RunSummaryRowBuilder.build_rows_from(summary, lobby, "", ["u1"])
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["player_id"], "u1")

func test_summary_rows_player_missing_from_lobby_falls_back_to_pid():
	# Defensive: an ordered id that has a tally but no lobby row (a
	# wire-payload race rebuilds the lobby roster but leaves the
	# session's player_ids array stale). Row still renders with
	# kitten_name == player_id so the UI doesn't drop a row that has
	# real XP data.
	var bc := XPBroadcaster.new()
	bc.register_player("u_ghost")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(8, "u_ghost")
	var rows := RunSummaryRowBuilder.build_rows_from(summary, null, "", ["u_ghost"])
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["player_id"], "u_ghost")
	assert_eq(rows[0]["kitten_name"], "u_ghost", "fallback to pid when no lobby row")
	assert_eq(rows[0]["class_name"], "")
	assert_false(rows[0]["is_host"])
	assert_eq(rows[0]["xp_earned"], 8)

func test_summary_rows_empty_kitten_name_falls_back_to_pid():
	# Half-populated wire payload: lobby row exists but kitten_name is
	# empty. Same fallback as the no-lobby path — the UI doesn't render
	# a blank name field.
	var lobby := _make_lobby_for_summary([["u1", "", "Mage"]])
	var rows := RunSummaryRowBuilder.build_rows_from(null, lobby, "", ["u1"])
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["kitten_name"], "u1", "empty kitten_name falls back to pid")
	assert_eq(rows[0]["class_name"], "Mage", "class still rendered from lobby")

func test_summary_rows_empty_player_id_skipped():
	# Defensive against a corrupted ordered_player_ids array — an empty
	# id can't key a row. Same shape as CoopSession._init's empty-id
	# skip. The non-empty ids around it still render.
	var lobby := _make_lobby_for_summary([["u1", "A", "Mage"]])
	var rows := RunSummaryRowBuilder.build_rows_from(null, lobby, "", ["", "u1", ""])
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["player_id"], "u1")

func test_summary_rows_empty_local_id_no_local_flag():
	# Default-constructed (test / pre-handshake / solo) session has
	# local_player_id == "". No row gets is_local=true; the UI
	# doesn't bold any row.
	var lobby := _make_lobby_for_summary([
		["u1", "A", "Mage"],
		["u2", "B", "Thief"],
	])
	var rows := RunSummaryRowBuilder.build_rows_from(null, lobby, "", ["u1", "u2"])
	for row in rows:
		assert_false(row["is_local"], "no row should be local when local_player_id is empty")

func test_summary_rows_local_flag_set_on_matching_row():
	# Exactly the row whose player_id matches local_player_id is
	# flagged. The other rows stay false even if their kitten_name
	# matches (kitten_name is not the key).
	var lobby := _make_lobby_for_summary([
		["u1", "Whiskers", "Mage"],
		["u2", "Whiskers", "Thief"],  # same display name, different id
	])
	var rows := RunSummaryRowBuilder.build_rows_from(null, lobby, "u2", ["u1", "u2"])
	assert_false(rows[0]["is_local"], "matching by kitten_name doesn't flag local")
	assert_true(rows[1]["is_local"])

func test_summary_rows_null_summary_renders_zero_xp():
	# Pre-run preview path: the summary tally hasn't been constructed
	# yet (or has been dropped via end()), but the lobby + ids are
	# known. Rows render with xp_earned == 0 across the board so the
	# UI can re-use the same row builder for "lobby preview" + "post-
	# run summary" without branching.
	var lobby := _make_lobby_for_summary([
		["u1", "A", "Mage"],
		["u2", "B", "Thief"],
	])
	var rows := RunSummaryRowBuilder.build_rows_from(null, lobby, "u1", ["u1", "u2"])
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["xp_earned"], 0)
	assert_eq(rows[1]["xp_earned"], 0)

func test_summary_rows_null_lobby_renders_pid_fallback_rows():
	# A test path that constructs only a tally + ids list still
	# produces rows. kitten_name falls back to pid; class_name == "";
	# is_host == false.
	var bc := XPBroadcaster.new()
	bc.register_player("u1")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(12, "u1")
	var rows := RunSummaryRowBuilder.build_rows_from(summary, null, "u1", ["u1"])
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["kitten_name"], "u1")
	assert_eq(rows[0]["class_name"], "")
	assert_false(rows[0]["is_host"])
	assert_eq(rows[0]["xp_earned"], 12)
	assert_true(rows[0]["is_local"])

func test_summary_rows_empty_ordered_ids_returns_empty():
	# Empty (not null — GDScript's static typing rejects null for an
	# Array parameter at parse time). A caller with no ids gets []
	# back; same empty-state branch as the null-session path.
	assert_eq(RunSummaryRowBuilder.build_rows_from(null, null, "", []), [])

func test_summary_rows_returned_array_is_fresh_allocation():
	# Caller should be able to mutate/sort the returned rows without
	# back-affecting subsequent build_rows calls. Pins that we don't
	# memoize and return a shared reference.
	var lobby := _make_lobby_for_summary([["u1", "A", "Mage"]])
	var rows1 := RunSummaryRowBuilder.build_rows_from(null, lobby, "u1", ["u1"])
	rows1.clear()
	var rows2 := RunSummaryRowBuilder.build_rows_from(null, lobby, "u1", ["u1"])
	assert_eq(rows2.size(), 1, "second call returns a fresh row even after caller cleared the first")

func test_summary_rows_grand_total_sums_xp_earned():
	# grand_total_for_rows agrees with RunXPSummary.grand_total when
	# the row builder consumes the same tally. Pins the contract that
	# the UI's "+N XP party total" header doesn't have to re-read the
	# summary — it can sum the rows it just rendered.
	var lobby := _make_lobby_for_summary([
		["u1", "A", "Mage"],
		["u2", "B", "Thief"],
	])
	var bc := XPBroadcaster.new()
	bc.register_player("u1")
	bc.register_player("u2")
	var summary := RunXPSummary.new(bc)
	bc.on_enemy_killed(7, "u1")
	bc.on_enemy_killed(11, "u2")
	var rows := RunSummaryRowBuilder.build_rows_from(summary, lobby, "u1", ["u1", "u2"])
	# Both members each got 7 + 11 = 18; grand total = 36.
	assert_eq(RunSummaryRowBuilder.grand_total_for_rows(rows), summary.grand_total())
	assert_eq(RunSummaryRowBuilder.grand_total_for_rows(rows), 36)

func test_summary_rows_grand_total_empty_returns_zero():
	# Defensive against an empty rows array (UI render before session
	# is wired; or a session with no party). The Array parameter is
	# statically typed so null isn't a parse-valid input.
	assert_eq(RunSummaryRowBuilder.grand_total_for_rows([]), 0)

func test_summary_rows_build_from_active_session_end_to_end():
	# End-to-end: an active CoopSession's xp_summary tallies real
	# emissions, and the row builder pulls everything out via the
	# convenience entry point. Closes AC#5 on the data side: the UI
	# scene's render loop is `for row in build_rows(session)`.
	var lobby := _make_lobby_for_summary([
		["u1", "Whiskers", "Mage", true],
		["u2", "Mittens", "Thief"],
		["u3", "Patches", "Ninja"],
	])
	var c1 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k1")
	var c2 := CharacterData.make_new(CharacterData.CharacterClass.THIEF, "k2")
	var c3 := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "k3")
	var characters := {"u1": c1, "u2": c2, "u3": c3}
	var session := CoopSession.new(lobby, characters, null, null, "u2")
	session.start(_make_two_room_dungeon_for_apply())
	# A kill anywhere in the party fans out to all three.
	session.xp_broadcaster.on_enemy_killed(9, "u1")
	var rows := RunSummaryRowBuilder.build_rows(session)
	assert_eq(rows.size(), 3)
	# Order matches lobby join order.
	assert_eq(rows[0]["player_id"], "u1")
	assert_eq(rows[1]["player_id"], "u2")
	assert_eq(rows[2]["player_id"], "u3")
	# Local flag is on u2 (this client) only.
	assert_false(rows[0]["is_local"])
	assert_true(rows[1]["is_local"])
	assert_false(rows[2]["is_local"])
	# Host flag is on u1 only.
	assert_true(rows[0]["is_host"])
	assert_false(rows[1]["is_host"])
	assert_false(rows[2]["is_host"])
	# Each member earned 9 XP via fan-out.
	assert_eq(rows[0]["xp_earned"], 9)
	assert_eq(rows[1]["xp_earned"], 9)
	assert_eq(rows[2]["xp_earned"], 9)
	assert_eq(RunSummaryRowBuilder.grand_total_for_rows(rows), 27)

# --- RunSummaryHeaderBuilder ----------------------------------------------

func _row(pid: String, name: String, xp: int, is_local: bool = false, is_host: bool = false) -> Dictionary:
	# Matches the row shape RunSummaryRowBuilder produces. Lets the
	# header tests pin behavior against a hand-crafted rows array
	# without re-exercising the row builder's lobby-join logic.
	return {
		"player_id": pid,
		"kitten_name": name,
		"class_name": "Mage",
		"xp_earned": xp,
		"is_local": is_local,
		"is_host": is_host,
	}

func test_summary_header_null_session_returns_empty_header():
	# Pre-handshake / test path with no session at all. UI's empty-state
	# placeholder branch reads the header without a null-check; the
	# keys must still be present with zero / empty / false values.
	var header := RunSummaryHeaderBuilder.build_header(null)
	assert_eq(header["party_size"], 0)
	assert_eq(header["grand_total_xp"], 0)
	assert_eq(header["mvp_player_id"], "")
	assert_eq(header["mvp_kitten_name"], "")
	assert_eq(header["mvp_xp_earned"], 0)
	assert_eq(header["floor_level"], 1)
	assert_eq(header["local_player_id"], "")
	assert_eq(header["local_kitten_name"], "")
	assert_eq(header["local_xp_earned"], 0)
	assert_false(header["has_local_player"])
	assert_false(header["dungeon_completed"])
	assert_eq(header["completion_grant"], 0)

func test_summary_header_empty_rows_returns_empty_header_shape():
	# Empty rows array still produces every header key; the UI doesn't
	# branch on a missing key. Floor level + completion grant are the
	# caller's choice; pin that they pass through (vs. always-1 floor).
	var header := RunSummaryHeaderBuilder.build_header_from([], 3, 0)
	assert_eq(header["party_size"], 0)
	assert_eq(header["grand_total_xp"], 0)
	assert_eq(header["mvp_player_id"], "")
	assert_eq(header["mvp_xp_earned"], 0)
	assert_eq(header["floor_level"], 3)
	assert_false(header["has_local_player"])
	assert_false(header["dungeon_completed"])

func test_summary_header_party_size_matches_rows_count():
	# party_size mirrors rows.size() — UI's "+N kittens crawled" line
	# reads it directly.
	var rows := [
		_row("u1", "A", 5),
		_row("u2", "B", 3),
		_row("u3", "C", 8),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(header["party_size"], 3)

func test_summary_header_grand_total_xp_sums_rows():
	# grand_total_xp agrees with RunSummaryRowBuilder.grand_total_for_rows.
	# UI's "+N XP party total" reads from the header, no re-iteration.
	var rows := [
		_row("u1", "A", 5),
		_row("u2", "B", 3),
		_row("u3", "C", 8),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(header["grand_total_xp"], 16)
	assert_eq(header["grand_total_xp"], RunSummaryRowBuilder.grand_total_for_rows(rows))

func test_summary_header_mvp_picks_highest_xp():
	# Highest xp_earned wins MVP. Pinned end-to-end: pid + name + xp
	# all come from the same row. UI renders "MVP: <name> +<xp> XP".
	var rows := [
		_row("u1", "Whiskers", 5),
		_row("u2", "Mittens", 30),
		_row("u3", "Patches", 12),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(header["mvp_player_id"], "u2")
	assert_eq(header["mvp_kitten_name"], "Mittens")
	assert_eq(header["mvp_xp_earned"], 30)

func test_summary_header_mvp_tie_goes_to_first_in_array_order():
	# Ties go to the first row in array order (lobby join order from
	# RunSummaryRowBuilder). Deterministic across renders — a re-render
	# produces the same MVP. Reverse the array and the MVP changes.
	var rows := [
		_row("u_first", "A", 7),
		_row("u_second", "B", 7),
		_row("u_third", "C", 7),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(header["mvp_player_id"], "u_first", "first-in-array wins on tie")
	# Reversed order -> reversed MVP. Confirms tie-break is purely positional.
	var rows_rev := [
		_row("u_third", "C", 7),
		_row("u_second", "B", 7),
		_row("u_first", "A", 7),
	]
	var header_rev := RunSummaryHeaderBuilder.build_header_from(rows_rev, 1, 0)
	assert_eq(header_rev["mvp_player_id"], "u_third")

func test_summary_header_no_mvp_when_all_rows_zero_xp():
	# A run where nobody earned XP shouldn't crown anyone — UI hides
	# the MVP line. Pinned by "" / 0 fields rather than first-row
	# fallback (which would lie about achievement).
	var rows := [
		_row("u1", "A", 0),
		_row("u2", "B", 0),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(header["mvp_player_id"], "", "no MVP when nobody scored")
	assert_eq(header["mvp_kitten_name"], "")
	assert_eq(header["mvp_xp_earned"], 0)

func test_summary_header_no_mvp_when_rows_empty():
	# Same as the all-zero case but for the size-0 rows array. UI's
	# MVP-line gate `mvp_player_id != ""` works for both.
	var header := RunSummaryHeaderBuilder.build_header_from([], 1, 0)
	assert_eq(header["mvp_player_id"], "")
	assert_eq(header["mvp_xp_earned"], 0)

func test_summary_header_floor_level_passes_through():
	# floor_level is the caller's choice (PartyScaler.compute_floor
	# result on session). Pin that it passes through unchanged — the
	# header doesn't re-compute / clamp it.
	var rows := [_row("u1", "A", 5)]
	assert_eq(RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)["floor_level"], 1)
	assert_eq(RunSummaryHeaderBuilder.build_header_from(rows, 5, 0)["floor_level"], 5)
	assert_eq(RunSummaryHeaderBuilder.build_header_from(rows, 17, 0)["floor_level"], 17)

func test_summary_header_local_fields_set_on_local_row():
	# When a row has is_local=true, its pid + name + xp populate the
	# header's local_* fields. UI's "Your contribution: <name> +<xp>"
	# line reads from the header.
	var rows := [
		_row("u1", "A", 5),
		_row("u2", "Mittens", 12, true),
		_row("u3", "C", 9),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_true(header["has_local_player"])
	assert_eq(header["local_player_id"], "u2")
	assert_eq(header["local_kitten_name"], "Mittens")
	assert_eq(header["local_xp_earned"], 12)

func test_summary_header_no_local_player_when_no_local_row():
	# Default-constructed / pre-handshake / solo-mode session: no row
	# has is_local=true. has_local_player is false; local_* fields are
	# empty / 0. UI's "Your contribution" line is hidden.
	var rows := [
		_row("u1", "A", 5),
		_row("u2", "B", 12),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_false(header["has_local_player"])
	assert_eq(header["local_player_id"], "")
	assert_eq(header["local_kitten_name"], "")
	assert_eq(header["local_xp_earned"], 0)

func test_summary_header_local_player_can_be_mvp():
	# The local player can also be the MVP. The two computations are
	# independent — local_* tracks "you," mvp_* tracks "highest scorer."
	# Pinned because the UI might render both lines and they'd both
	# point at the same row.
	var rows := [
		_row("u1", "A", 5),
		_row("u2", "Mittens", 99, true),
		_row("u3", "C", 12),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(header["mvp_player_id"], "u2")
	assert_eq(header["local_player_id"], "u2")
	assert_eq(header["mvp_xp_earned"], 99)
	assert_eq(header["local_xp_earned"], 99)

func test_summary_header_completion_grant_drives_dungeon_completed():
	# completion_grant > 0 => dungeon_completed=true. UI's "Victory!"
	# vs "Defeat" header gate reads from dungeon_completed; pin that
	# the two fields agree (no contract drift).
	var rows := [_row("u1", "A", 5)]
	var won := RunSummaryHeaderBuilder.build_header_from(rows, 1, 1)
	assert_true(won["dungeon_completed"])
	assert_eq(won["completion_grant"], 1)
	var lost := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_false(lost["dungeon_completed"])
	assert_eq(lost["completion_grant"], 0)

func test_summary_header_negative_completion_grant_clamps_to_zero():
	# Defensive against an upstream contract violation. The header is
	# the canonical source for the UI's "Victory" branch; a negative
	# grant must not flip dungeon_completed=true. Treated as "no
	# completion."
	var rows := [_row("u1", "A", 5)]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, -3)
	assert_false(header["dungeon_completed"])
	assert_eq(header["completion_grant"], 0)

func test_summary_header_skips_non_dictionary_rows():
	# Defensive against a malformed rows array (caller mutated it
	# between build_rows and build_header). Non-dict entries are
	# silently skipped — the well-formed rows still drive the header.
	var rows: Array = [
		_row("u1", "A", 5),
		"garbage",  # skipped
		null,  # skipped
		_row("u2", "B", 12),
	]
	var header := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(header["party_size"], 4, "party_size mirrors rows.size() raw — UI's count line")
	assert_eq(header["mvp_player_id"], "u2")
	assert_eq(header["grand_total_xp"], 17)

func test_summary_header_returned_dict_is_fresh_allocation():
	# Caller can mutate the returned header without back-affecting a
	# subsequent build. Pins that we don't memoize.
	var rows := [_row("u1", "A", 5)]
	var h1 := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	h1["grand_total_xp"] = 99999
	var h2 := RunSummaryHeaderBuilder.build_header_from(rows, 1, 0)
	assert_eq(h2["grand_total_xp"], 5, "second call returns fresh dict; first call's mutation didn't leak")

func test_summary_header_build_from_active_session_end_to_end():
	# End-to-end: an active CoopSession's xp_summary tallies real
	# emissions, and the header builder pulls everything out via the
	# convenience entry point. Closes the AC#5 data side: the UI's
	# header binding is `var header = build_header(session)`.
	var lobby := _make_lobby_for_summary([
		["u1", "Whiskers", "Mage", true],
		["u2", "Mittens", "Thief"],
		["u3", "Patches", "Ninja"],
	])
	var c1 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k1")
	var c2 := CharacterData.make_new(CharacterData.CharacterClass.THIEF, "k2")
	var c3 := CharacterData.make_new(CharacterData.CharacterClass.NINJA, "k3")
	var characters := {"u1": c1, "u2": c2, "u3": c3}
	var session := CoopSession.new(lobby, characters, null, null, "u2")
	session.start(_make_two_room_dungeon_for_apply())
	# All three are L1, so floor scales to L1 (no scaling).
	# A kill anywhere fans out 9 XP to all three; everybody ties.
	session.xp_broadcaster.on_enemy_killed(9, "u1")
	var header := RunSummaryHeaderBuilder.build_header(session)
	assert_eq(header["party_size"], 3)
	assert_eq(header["grand_total_xp"], 27)
	# Ties go to the first in lobby join order (u1).
	assert_eq(header["mvp_player_id"], "u1")
	assert_eq(header["mvp_kitten_name"], "Whiskers")
	assert_eq(header["mvp_xp_earned"], 9)
	# Local row is u2 / Mittens.
	assert_true(header["has_local_player"])
	assert_eq(header["local_player_id"], "u2")
	assert_eq(header["local_kitten_name"], "Mittens")
	assert_eq(header["local_xp_earned"], 9)
	# Floor scales to 1 (everyone L1).
	assert_eq(header["floor_level"], 1)
	# No completion fired yet (boss room not cleared via this test).
	assert_false(header["dungeon_completed"])
	assert_eq(header["completion_grant"], 0)

func test_summary_header_post_completion_grant_visible():
	# After the boss-cleared edge fires DungeonRunCompletion.complete,
	# session.last_completion_grant() is non-zero and the header
	# surfaces it. Drives the "+N tokens" toast on the summary screen.
	# Doesn't actually clear a boss room here — _on_dungeon_completed
	# is the call DungeonRunController would route to; we hand-fire it
	# via session.run_controller.dungeon_completed.emit() to pin the
	# wire from completion-edge -> session._last_completion_grant ->
	# header.
	var lobby := _make_lobby_for_summary([["u1", "A", "Mage"]])
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var characters := {"u1": c}
	var inv := TokenInventory.new()
	var session := CoopSession.new(lobby, characters, null, inv, "u1")
	session.start(_make_two_room_dungeon_for_apply())
	# Trigger the completion path (registers a dungeon_complete in the
	# meta tracker if non-null + drips a token to the inventory).
	session.run_controller.dungeon_completed.emit()
	var header := RunSummaryHeaderBuilder.build_header(session)
	assert_true(header["dungeon_completed"])
	assert_eq(header["completion_grant"], 1)

func test_summary_header_passes_through_post_end_session():
	# Same dead-after-end caveat as RunSummaryRowBuilder. After end()
	# drops xp_summary, the row builder still produces rows from
	# lobby + player_ids (with xp_earned == 0 across the board), and
	# the header still produces a valid shape — floor_level + last
	# completion grant survive end().
	var lobby := _make_lobby_for_summary([
		["u1", "Whiskers", "Mage"],
		["u2", "Mittens", "Thief"],
	])
	var c1 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k1")
	var c2 := CharacterData.make_new(CharacterData.CharacterClass.THIEF, "k2")
	var session := CoopSession.new(lobby, {"u1": c1, "u2": c2}, null, null, "u1")
	session.start(_make_two_room_dungeon_for_apply())
	session.xp_broadcaster.on_enemy_killed(9, "u1")
	# Read the header BEFORE end() drops the tally — captures the
	# canonical "what the UI would render" snapshot.
	var live := RunSummaryHeaderBuilder.build_header(session)
	assert_eq(live["grand_total_xp"], 18)
	# After end() the tally is gone but rows still render with 0 XP.
	session.end()
	var post := RunSummaryHeaderBuilder.build_header(session)
	assert_eq(post["party_size"], 2, "rows still produced from lobby + player_ids")
	assert_eq(post["grand_total_xp"], 0, "tally is gone post-end")
	assert_eq(post["mvp_player_id"], "", "no MVP when nobody scored (tally dropped)")
