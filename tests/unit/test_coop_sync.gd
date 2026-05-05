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
