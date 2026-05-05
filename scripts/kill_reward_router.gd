class_name KillRewardRouter
extends RefCounted

# Single seam for "the local player just killed an enemy". Branches
# between the solo and co-op reward paths so Player.gd doesn't have to
# carry the conditional inline. Pure data — RefCounted with one static
# method, same shape as DungeonRunCompletion / TokenGrantRules.
#
# Solo path (no active co-op session):
#   - Applies XP locally via ProgressionSystem.add_xp against the
#     killer's CharacterData.
#   - Grants the full TokenGrantRules.tokens_for_kill (milestone-
#     crossing + boss-kill bonus) to the inventory.
#
# Co-op path (session.is_active() AND broadcaster non-null AND
# local_player_id non-empty):
#   - Broadcasts XP via session.xp_broadcaster.on_enemy_killed. Every
#     party member gets an xp_awarded(player_id, amount) emission;
#     the LocalXPRouter on each client filters by its own player_id
#     and applies the amount to its member.real_stats. The local
#     emission lands on this client's CharacterData via the same
#     CharacterData reference held by Player.gd (member.real_stats
#     === Player.data at construction time).
#   - Grants ONLY the boss-kill bonus locally. The milestone-token
#     drip fires from LocalTokenGrantRouter on the level_up edge —
#     putting it here too would double-grant the milestone for a
#     local kill that crosses a milestone level. The boss bonus
#     stays local because it follows the kill, not the XP fan-out:
#     a remote-killer awarding XP to me does not grant me a boss
#     bonus token, only the killer earns it. Same rule as
#     LocalTokenGrantRouter's "does NOT grant boss-kill bonus"
#     contract — the rule lives here on the killer side.
#
# Returns the number of tokens granted to the inventory on this call
# (for a future "+N tokens" toast that wants the per-event count
# without diffing the inventory). Solo path may return milestone +
# boss combined; co-op path returns 0 or boss-bonus only.
#
# Null-safe across the board: null data / enemy_data / inventory /
# session / empty local_player_id all degrade to a no-op return 0.
# Lets test paths and pre-handshake co-op paths share the helper
# without crashing.

# Whether the "co-op active" branch should fire. Pulled out as a
# static so a test can pin the predicate without exercising the
# whole reward path. A session that exists but isn't active (e.g.
# constructed but start() not yet called, or already end()ed) takes
# the solo branch — the broadcaster is null in those windows so
# routing via it would no-op anyway, but the explicit gate makes
# the test contract clearer.
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
	inventory: TokenInventory,
	session: CoopSession,
	local_player_id: String
) -> int:
	if data == null or enemy_data == null:
		return 0
	if is_coop_route(session, local_player_id):
		session.xp_broadcaster.on_enemy_killed(enemy_data.xp_reward, local_player_id)
		# Boss-kill bonus stays on the killer's local inventory.
		# Milestone tokens flow through LocalTokenGrantRouter on the
		# level_up edge — adding tokens_for_level_up here would
		# double-grant for a local-kill that crosses a milestone.
		if inventory != null and enemy_data.is_boss:
			var boss_bonus := TokenGrantRules.tokens_for_boss_kill()
			inventory.grant(boss_bonus)
			return boss_bonus
		return 0
	# Solo path — apply XP locally + grant the combined kill rule.
	var level_before := data.level
	ProgressionSystem.add_xp(data, enemy_data.xp_reward)
	if inventory == null:
		return 0
	var earned := TokenGrantRules.tokens_for_kill(enemy_data, level_before, data.level)
	if earned > 0:
		inventory.grant(earned)
	return earned
