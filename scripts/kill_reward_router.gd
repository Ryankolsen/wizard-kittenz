class_name KillRewardRouter
extends RefCounted

# Single seam for "the local player just killed an enemy". Branches
# between the solo and co-op kill paths so Player.gd doesn't have to
# carry the conditional inline. Pure data — RefCounted with one static
# method, same shape as DungeonRunCompletion.
#
# Solo path (no active co-op session):
#   - Applies XP locally via ProgressionSystem.add_xp against the
#     killer's CharacterData.
#   - Tallies the kill's xp_reward into the offline counter so the sync
#     orchestrator can fold it into the server record on reconnect.
#
# Co-op path (session.is_active() AND broadcaster non-null AND
# local_player_id non-empty):
#   - Broadcasts XP via session.xp_broadcaster.on_enemy_killed. Every
#     party member gets an xp_awarded(player_id, amount) emission;
#     the LocalXPRouter on each client filters by its own player_id
#     and applies the amount to its member.real_stats.
#   - Marks the enemy dead in the per-session EnemyStateSyncManager
#     registry so the local kill detection and the wire layer's
#     remote enemy-died packet converge through the same idempotent
#     apply_death(enemy_id) path. Empty enemy_id (pre-spawn-layer /
#     test fixture) skips the registry poke.
#   - Offline XP counter is intentionally NOT incremented in the co-op
#     path: co-op requires the network, so the XP earned here is
#     already "synced" — folding it into pending_xp would double-count
#     when the next solo-mode merge fires.
#
# Null-safe across the board: null data / enemy_data / session / empty
# local_player_id all degrade to a no-op. Lets test paths and pre-
# handshake co-op paths share the helper without crashing.

# Whether the "co-op active" branch should fire. Pulled out as a
# static so a test can pin the predicate without exercising the
# whole reward path.
static func is_coop_route(session: CoopSession, local_player_id: String) -> bool:
	if session == null:
		return false
	if not session.is_active():
		return false
	if session.xp_broadcaster == null:
		return false
	if local_player_id == "":
		return false
	return true

static func route_kill(
	data: CharacterData,
	enemy_data: EnemyData,
	session: CoopSession,
	local_player_id: String,
	xp_tracker: OfflineXPTracker = null,
	lobby: NakamaLobby = null,
	ledger: CurrencyLedger = null
) -> void:
	if data == null or enemy_data == null:
		return
	# Gold drop (PRD #53). Credit the local CurrencyLedger by the enemy's
	# gold_reward on every kill — full amount in both solo and co-op (Gold
	# is per-character, not party-split). Null ledger (pre-wiring callers /
	# tests that don't care about Gold) is a silent no-op.
	if ledger != null:
		ledger.credit(enemy_data.gold_reward, CurrencyLedger.Currency.GOLD)
	if is_coop_route(session, local_player_id):
		# Party XP split: each member receives floor(xp_reward / party_size)
		# rather than the full reward. Both the local broadcast and the wire
		# packet carry the per-player amount, so the receiver's RemoteKillApplier
		# fans out the same per-player share without needing to know party
		# size again. Solo-coop (party_size == 1) keeps the full reward.
		var per_player := xp_per_player(enemy_data.xp_reward, session.xp_broadcaster.player_count())
		session.xp_broadcaster.on_enemy_killed(per_player, local_player_id)
		# Mark the enemy dead in the per-session network registry so the
		# remote enemy-died packet and the local kill detection converge
		# cleanly. apply_death is idempotent — if the remote packet beat
		# us, the second call returns false rather than erroring. Empty
		# enemy_id is a pre-spawn-layer / test fixture path; skip the
		# registry poke so we don't pollute it with an unkeyed entry.
		if session.enemy_sync != null and enemy_data.enemy_id != "":
			session.enemy_sync.apply_death(enemy_data.enemy_id)
		# Outbound wire send — fire-and-forget so a slow Nakama RTT
		# doesn't stall the kill flow. lobby == null is the test path /
		# pre-handshake path (no socket yet); send_kill_async also
		# null-checks its own socket internally so a disconnect mid-kill
		# is a silent no-op rather than a crash. Empty enemy_id is
		# already a no-op inside send_kill_async — caller doesn't need
		# to repeat the gate here.
		if lobby != null:
			lobby.send_kill_async(enemy_data.enemy_id, local_player_id, per_player)
		return
	# Solo path — apply XP locally and tally into the offline tracker.
	ProgressionSystem.add_xp(data, enemy_data.xp_reward)
	if xp_tracker != null:
		xp_tracker.record(enemy_data.xp_reward)

# Pure split helper. floor(xp_total / max(1, party_size)) so a 1-player
# co-op session keeps the full reward and odd totals (e.g. 100 / 3)
# floor-divide cleanly per AC. Exposed as a static so RoomClearWatcher
# and Player.collect_power_up share the same formula rather than
# duplicating the divide inline.
static func xp_per_player(xp_total: int, party_size: int) -> int:
	if party_size <= 1:
		return xp_total
	return xp_total / party_size
