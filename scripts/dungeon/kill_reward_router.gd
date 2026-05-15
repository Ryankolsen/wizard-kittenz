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
# Co-op path (session.is_routing_ready()):
#   - Broadcasts XP via session.xp_broadcaster.on_enemy_killed. Every
#     party member gets an xp_awarded(player_id, amount) emission;
#     the CoopXPSubscriber on each client filters by its own player_id
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

static func route_kill(
	data: CharacterData,
	enemy_data: EnemyData,
	session: CoopSession,
	local_player_id: String,
	xp_tracker: OfflineXPTracker = null,
	lobby: NakamaLobby = null,
	ledger: CurrencyLedger = null,
	rng: RandomNumberGenerator = null
) -> ItemData:
	if data == null or enemy_data == null:
		return null
	# Gold drop (PRD #53). Credit the local CurrencyLedger by the enemy's
	# gold_reward on every kill — full amount in both solo and co-op (Gold
	# is per-character, not party-split). Null ledger (pre-wiring callers /
	# tests that don't care about Gold) is a silent no-op.
	if ledger != null:
		ledger.credit(enemy_data.gold_reward, CurrencyLedger.Currency.GOLD)
		# Luck flat gold bonus (PRD #85 / issue #90). +1 gold per luck point
		# on every kill — stacks with the base gold credit above. luck<=0
		# returns 0 inside gold_bonus, so the credit is a no-op for any
		# character/enemy that ships luck=0.
		var luck_gold := LuckRewardModifier.gold_bonus(data.luck)
		if luck_gold > 0:
			ledger.credit(luck_gold, CurrencyLedger.Currency.GOLD)
	# Item drop (PRD #73 / issue #79). Resolve via the rarity-gated drop
	# table. Boss kills always produce an item; regular kills ~10%. The
	# router does not mutate ItemInventory — it returns the ItemData so
	# the caller (Player) can decide between auto-equip / equip prompt /
	# auto-bag based on inventory state.
	var drop_context: int = ItemDropResolver.Context.BOSS if enemy_data.is_boss else ItemDropResolver.Context.ENEMY
	var item_drop: ItemData = ItemDropResolver.resolve(data.level, drop_context, rng)
	# Luck rarity bump (PRD #85 / issue #90). Reuse the same rng so a
	# seeded test can pin both the resolver roll and the bump roll. Null
	# item, luck<=0, or EPIC-tier drops all pass through untouched inside
	# bump_item — no extra gating needed here.
	item_drop = LuckRewardModifier.bump_item(item_drop, data.luck, rng)
	if session != null and session.is_routing_ready():
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
		return item_drop
	# Solo path — apply XP locally and tally into the offline tracker.
	# Passing the ledger threads the LEVEL_UP_GEM_REWARD credit through any
	# level-ups that this kill triggers (PRD #53 / issue #67).
	ProgressionSystem.add_xp(data, enemy_data.xp_reward, ledger)
	if xp_tracker != null:
		xp_tracker.record(enemy_data.xp_reward)
	return item_drop

# Pure split helper. floor(xp_total / max(1, party_size)) so a 1-player
# co-op session keeps the full reward and odd totals (e.g. 100 / 3)
# floor-divide cleanly per AC. Exposed as a static so RoomClearWatcher
# and Player.collect_power_up share the same formula rather than
# duplicating the divide inline.
static func xp_per_player(xp_total: int, party_size: int) -> int:
	if party_size <= 1:
		return xp_total
	return xp_total / party_size
