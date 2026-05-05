class_name RunSummaryHeaderBuilder
extends RefCounted

# Sibling to RunSummaryRowBuilder. Where the row builder produces the
# per-player rows for the end-of-run summary screen, this helper
# produces the header dict the screen renders above the row list:
# party total XP, MVP, floor level, completion grant. Single static
# seam so the future summary screen scene's header binding is a
# one-liner — the recurring "RunSummaryHeaderBuilder is a separate
# concern" gap mentioned in ec0616b's commit notes closes here.
#
# Sibling-shaped to RunSummaryRowBuilder: RefCounted, all-static, no
# I/O, no scene tree. Two entry points:
#   - build_header(session) — convenience that pulls everything from
#     the CoopSession in one call (rows + floor_level + last
#     completion grant).
#   - build_header_from(rows, floor_level, completion_grant) —
#     primitive that takes the three ingredients directly so a test
#     can pin the header shape without booting a full session.
#
# Header shape (Dictionary):
#   - party_size: int            number of rendered rows
#   - grand_total_xp: int        sum of xp_earned across rows
#   - mvp_player_id: String      row with the highest xp_earned;
#                                ties go to the first row in array
#                                order (lobby join order from
#                                RunSummaryRowBuilder); empty when
#                                there are no rows OR every row has
#                                xp_earned == 0 (no MVP — UI hides
#                                the MVP line entirely rather than
#                                rendering "MVP: <random>" against a
#                                room where nobody scored)
#   - mvp_kitten_name: String    kitten_name from the MVP row;
#                                empty when no MVP
#   - mvp_xp_earned: int         xp_earned from the MVP row;
#                                0 when no MVP
#   - floor_level: int           party scaling floor for the run
#                                (PartyScaler.compute_floor result)
#   - local_player_id: String    passthrough — empty when the session
#                                doesn't know which pid is local
#                                (default-constructed / solo)
#   - local_kitten_name: String  kitten_name from the local row;
#                                empty when no local row in rows
#                                (default-constructed / pre-handshake)
#   - local_xp_earned: int       xp_earned from the local row;
#                                0 when no local row
#   - has_local_player: bool     any row.is_local; UI's gate for
#                                "show your contribution line"
#   - dungeon_completed: bool    completion_grant > 0; UI's gate for
#                                "Victory!" vs "Defeat" header
#   - completion_grant: int      tokens granted on completion (0 on
#                                a non-completion / pre-completion
#                                read); UI surfaces "+N tokens" toast
#
# Why MVP ties go to first-by-array-order (vs. local-player-first or
# random):
#   - Deterministic across renders. A re-render of the same rows
#     produces the same MVP. Lobby join order is the row order the
#     player was looking at before the run started; an MVP that
#     changes per render would surprise the user.
#   - "Local player wins ties" would be UI-friendly but inconsistent
#     across clients (each client would see itself as MVP on a tie),
#     which would be confusing in chat / screenshots.
#   - The future "rank by XP" sort (RunSummaryRowSorter or similar) is
#     a separate concern — the header MVP is computed off the rows
#     in their existing order, not a re-sorted copy.
#
# Why "all-zero rows produce no MVP" (vs. picking row 0):
#   - A run where nobody scored XP shouldn't crown anyone. UI hides
#     the MVP line; rendering "MVP: <first row>: +0 XP" would lie
#     about achievement. Pinned by test.
#
# What this does NOT do:
#   - Compute the rows. Caller passes a pre-built rows array (from
#     RunSummaryRowBuilder.build_rows / build_rows_from). Same
#     decoupling rationale as RunSummaryRowBuilder.grand_total_for_
#     rows: the UI builds rows once, then derives both the rendered
#     list and the header from the same source.
#   - Sort the rows. The supplied order wins (MVP tie-breaking uses
#     it). If the UI wants "rank by XP," that's a sibling helper
#     consumed before this one.
#   - Format strings. Numbers stay as ints; the UI applies its own
#     number formatter (e.g. "+1,234 XP"). Same shape rationale as
#     RunSummaryRowBuilder.
#   - Compute kills_for / damage_dealt_for / heals_for. RunXPSummary
#     tallies XP only. When the data layer grows sibling tallies, the
#     header grows the per-player MVP field shape (e.g. mvp_kills,
#     mvp_damage). The fan-out broadcasters would be siblings to
#     XPBroadcaster.
#   - Mutate the inputs. The returned header is a fresh allocation;
#     caller can mutate / serialize without back-affecting subsequent
#     calls.

# Convenience: pulls everything from the session in one call. Returns
# an empty header on a null session. Same null-safety shape as
# RunSummaryRowBuilder.build_rows.
#
# Note: works on an active OR ended session. After CoopSession.end(),
# `xp_summary` is null but `lobby` + `player_ids` + `local_player_id`
# + `floor_level` + `_last_completion_grant` survive — so a
# "play again" / "view summary" UI flow that lands AFTER end() still
# gets a populated header (with grand_total_xp == 0 because the tally
# is gone). Same dead-after-end caveat as RunSummaryRowBuilder.
static func build_header(session: CoopSession) -> Dictionary:
	if session == null:
		return _empty_header()
	var rows := RunSummaryRowBuilder.build_rows(session)
	return build_header_from(rows, session.floor_level, session.last_completion_grant())

# Primitive: takes the three ingredients directly. Lets a test drive
# the header shape without constructing a full CoopSession + Dungeon.
static func build_header_from(
	rows: Array,
	floor_level: int,
	completion_grant: int,
) -> Dictionary:
	var party_size: int = rows.size()
	var grand_total_xp: int = RunSummaryRowBuilder.grand_total_for_rows(rows)
	var mvp_player_id: String = ""
	var mvp_kitten_name: String = ""
	var mvp_xp_earned: int = 0
	var local_player_id: String = ""
	var local_kitten_name: String = ""
	var local_xp_earned: int = 0
	var has_local_player: bool = false
	for row in rows:
		if not (row is Dictionary):
			continue
		var xp: int = int(row.get("xp_earned", 0))
		# Strict > so ties go to the first row in array order. A row
		# with xp == 0 never wins MVP because mvp_xp_earned starts at
		# 0; the "all-zero rows produce no MVP" contract follows
		# directly.
		if xp > mvp_xp_earned:
			mvp_xp_earned = xp
			mvp_player_id = String(row.get("player_id", ""))
			mvp_kitten_name = String(row.get("kitten_name", ""))
		if bool(row.get("is_local", false)):
			has_local_player = true
			local_player_id = String(row.get("player_id", ""))
			local_kitten_name = String(row.get("kitten_name", ""))
			local_xp_earned = xp
	# completion_grant is the count granted on dungeon completion
	# (DungeonRunCompletion.complete returns this; CoopSession holds it
	# as last_completion_grant after the dungeon_completed signal). A
	# negative value would be a contract violation upstream — clamp to
	# 0 so the header is the canonical source for the UI's "Victory!"
	# branch (completion_grant > 0).
	var grant: int = completion_grant if completion_grant > 0 else 0
	return {
		"party_size": party_size,
		"grand_total_xp": grand_total_xp,
		"mvp_player_id": mvp_player_id,
		"mvp_kitten_name": mvp_kitten_name,
		"mvp_xp_earned": mvp_xp_earned,
		"floor_level": floor_level,
		"local_player_id": local_player_id,
		"local_kitten_name": local_kitten_name,
		"local_xp_earned": local_xp_earned,
		"has_local_player": has_local_player,
		"dungeon_completed": grant > 0,
		"completion_grant": grant,
	}

# Empty-state header. Same shape as a populated header but with
# every field zero / empty / false. UI's empty-state placeholder
# branch reads this without a special-case "is the header null"
# check — the keys are always present.
static func _empty_header() -> Dictionary:
	return {
		"party_size": 0,
		"grand_total_xp": 0,
		"mvp_player_id": "",
		"mvp_kitten_name": "",
		"mvp_xp_earned": 0,
		"floor_level": 1,
		"local_player_id": "",
		"local_kitten_name": "",
		"local_xp_earned": 0,
		"has_local_player": false,
		"dungeon_completed": false,
		"completion_grant": 0,
	}
