class_name RunSummaryRowBuilder
extends RefCounted

# Flattens a finished co-op run's data layer (RunXPSummary + LobbyState +
# local_player_id + ordered party ids) into the row list the end-of-run
# summary screen renders. Single static seam so the future summary scene
# (#17 AC#5: "End-of-run screen shows XP earned by each player") is a
# pure rendering loop over `build_rows(session)`.
#
# Closes the recurring "End-of-run summary screen scene — pure rendering
# job once the data layer is live" gap mentioned across the recent
# tracer-bullet commits (45f683c / f8c79ad / fb93ba8 / etc.). The
# join-with-lobby step (player_id -> kitten_name + class_name + is_host)
# was a lurking inline branch that every UI iteration would re-derive;
# pulling it into a pure-data helper means a UI test fixture can pin
# the row shape end-to-end without booting a scene.
#
# Sibling-shaped to existing pure-data helpers (RunXPSummary,
# RoomSpawnPlanner, RemoteKillApplier): RefCounted, no I/O, no scene
# tree. Stateless — all methods are static.
#
# Row shape (Dictionary):
#   - player_id: String     stable per-account id (lobby key)
#   - kitten_name: String   display name from LobbyPlayer; falls back
#                           to player_id when not in the lobby (defensive
#                           against a wire-payload race where the
#                           summary tally has the id but the lobby
#                           roster was rebuilt without it)
#   - class_name: String    from LobbyPlayer.class_name_str ("" when
#                           not in lobby; UI hides the class icon)
#   - xp_earned: int        from RunXPSummary.total_for(player_id);
#                           0 when the player didn't earn anything
#                           (still renders — they were in the party,
#                           just got no kills)
#   - is_local: bool        local_player_id == player_id; UI bolds /
#                           appends "(You)" on the local row. Empty
#                           local_player_id (default-constructed
#                           session, solo path) means no row gets
#                           is_local=true
#   - is_host: bool         from LobbyPlayer.is_host; false when not
#                           in lobby (UI hides the host crown)
#
# Order matches the supplied ordered_player_ids array (CoopSession
# preserves lobby join order in `player_ids`). Same join-order rationale
# as CoopSession.player_ids vs Dictionary-key iteration: deterministic
# row order across renders, matches the lobby roster the player was
# looking at before the run started.
#
# Defensiveness:
#   - Null session => empty array (UI's guard: render the empty-state
#     "no run data yet" placeholder rather than crashing on the iterator).
#   - A player_id in ordered_player_ids that's missing from the lobby
#     still renders, with kitten_name == player_id as a fallback. Avoids
#     dropping a row that the tally has data for. Same shape as
#     RunXPSummary's "render every id we have a tally for" contract.
#   - A player_id present in the summary tally but NOT in
#     ordered_player_ids is dropped. The orderer is the source of truth
#     so a stale tally entry (a player who left mid-match and was
#     dropped from the lobby roster but not from the per-run tally)
#     doesn't render a ghost row. Pinned by test.
#   - Empty player_id in ordered_player_ids is skipped (defensive
#     against a corrupted lobby array; same shape as
#     CoopSession._init's empty-id skip). The Array parameter itself
#     is statically typed (non-null) — passing actual null is a parse
#     error, so the contract is "pass [] for empty" rather than null.
#   - Null lobby is allowed: rows still render with player_id as the
#     kitten_name fallback, "" class_name, false is_host. Lets a
#     test path that constructs only a tally + ids list still produce
#     rows.
#   - Null summary is allowed: rows render with xp_earned == 0. Lets
#     a "show the lobby roster before the run is live" preview reuse
#     the same row builder.
#
# What this does NOT do:
#   - Sort. The supplied order wins. If the UI wants "rank by XP" or
#     "local player first," that's a UI-level concern (and a sibling
#     helper or an in-place sort on the returned array; the array is
#     already a defensive copy).
#   - Compute "winner" / "MVP" flags. The end-of-run header is a
#     separate concern (a future RunSummaryHeaderBuilder or similar);
#     this helper only produces per-player rows.
#   - Format strings. Numbers stay as ints; the UI applies its own
#     number formatter (e.g. "+1,234 XP"). Same shape rationale as
#     PartyScaler.format_hud_level: localization-friendly later.
#   - Mutate the inputs. The returned array is a fresh allocation;
#     each row is a fresh Dictionary. Caller can sort / mutate /
#     serialize without back-affecting the session.

# Convenience: pulls everything from the session in one call. Returns
# an empty array on a null or default-constructed session (no lobby /
# no member ids). Same null-safety shape as RemoteKillApplier.apply.
#
# Note: works on an active OR ended session. After CoopSession.end(),
# `xp_summary` is null but `lobby` + `player_ids` + `local_player_id`
# survive — so a "play again" / "view summary" UI flow that lands
# AFTER end() still gets rows (with xp_earned == 0 across the board).
# A UI that wants to show the live tally must read before end() drops
# the summary reference.
static func build_rows(session: CoopSession) -> Array:
	if session == null:
		return []
	return build_rows_from(
		session.xp_summary,
		session.lobby,
		session.local_player_id,
		session.player_ids,
	)

# Primitive: takes the four ingredients directly. Lets a test drive
# the row shape without constructing a full CoopSession + Dungeon.
# ordered_player_ids is the source of truth for which rows render and
# in what order; the lobby is consulted only for the per-row name /
# class / host fields.
static func build_rows_from(
	summary: RunXPSummary,
	lobby: LobbyState,
	local_player_id: String,
	ordered_player_ids: Array,
) -> Array:
	var rows: Array = []
	for raw_id in ordered_player_ids:
		var pid: String = String(raw_id)
		# Empty id is a defensive skip — same shape as CoopSession's
		# empty-id filter on construction. A corrupted lobby array
		# can't produce a row with no key.
		if pid == "":
			continue
		var lp: LobbyPlayer = null
		if lobby != null:
			lp = lobby.find_player(pid)
		var name_str: String = pid
		var class_str: String = ""
		var host_flag: bool = false
		if lp != null:
			# Fall back to player_id when the lobby row exists but the
			# kitten_name field is empty (a half-populated wire payload).
			# Avoids rendering a blank row.
			if lp.kitten_name != "":
				name_str = lp.kitten_name
			class_str = lp.class_name_str
			host_flag = lp.is_host
		var xp: int = 0
		if summary != null:
			xp = summary.total_for(pid)
		rows.append({
			"player_id": pid,
			"kitten_name": name_str,
			"class_name": class_str,
			"xp_earned": xp,
			"is_local": local_player_id != "" and local_player_id == pid,
			"is_host": host_flag,
		})
	return rows

# Sums xp_earned across the rows. Same number a "+N XP party total"
# header would render. Pulled out as a static so the UI doesn't have
# to re-iterate the rows just to compute the sum, and so a test pins
# the contract that the per-row sum agrees with RunXPSummary.grand_total.
static func grand_total_for_rows(rows: Array) -> int:
	var sum: int = 0
	for row in rows:
		if row is Dictionary:
			sum += int(row.get("xp_earned", 0))
	return sum
