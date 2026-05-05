class_name LocalTokenGrantRouter
extends RefCounted

# Per-client revive-token grant subscriber. Subscribes to a
# LocalXPRouter's level_up signal (fired post-XP-application) and grants
# milestone-crossing tokens to the bound TokenInventory. Closes the
# "remote-killer XP that crosses my milestone level should still drip
# a token" loop on the receiving end.
#
# Why a separate router (vs. tucking the rule into LocalXPRouter):
#   - LocalXPRouter is the XP application seam. The token grant rule
#     happens to read level transitions, but it could grow other
#     inputs in the future (e.g. a "double tokens this dungeon" buff,
#     or a per-class milestone curve). Keeping it split lets each
#     router be tested in isolation and lets a future "guild XP cut"
#     subscriber slot in alongside without a refactor.
#   - Solo callers don't need this router (their kill flow grants
#     tokens directly in player.gd). Only the co-op session
#     constructs it. Same shape as LocalXPRouter — RefCounted, pure
#     data, bind/unbind/idempotent/null-safe.
#
# Why subscribe to LocalXPRouter.level_up (not XPBroadcaster.xp_awarded):
#   - The token rule needs the level transition (old_level, new_level).
#     LocalXPRouter is the place that knows both — it reads the local
#     member's real_stats.level before AND after XPSystem.award.
#   - Subscribing to xp_awarded directly would race the XP application:
#     by the time this subscriber runs, LocalXPRouter may or may not
#     have already mutated the member level (signal-callback order is
#     registration order, but that's a brittle thing to bank on).
#     Listening to a post-application signal makes the ordering
#     explicit.
#
# What this does NOT do:
#   - Grant boss-kill bonus tokens. That's the killer's responsibility
#     (boss bonus follows the kill, not the XP fan-out). The local
#     kill flow keeps TokenGrantRules.tokens_for_kill for the boss
#     branch; this router only handles milestone-from-broadcast XP.
#   - Persist the inventory. SaveManager owns persistence; the router
#     just mutates the inventory in place. End-of-run save still
#     captures the count.

var _router: LocalXPRouter = null
var _inventory: TokenInventory = null
# Tokens granted since the last reset, for tests / future "+N tokens"
# toast that wants to surface a per-event count rather than the
# aggregate inventory delta. Aggregate (not per-emission) so a
# multi-level dump that crosses two milestones reports the sum.
var granted_total: int = 0

func _init(router: LocalXPRouter = null, inventory: TokenInventory = null) -> void:
	if router != null and inventory != null:
		bind(router, inventory)

# Subscribes to the router's level_up signal. Returns true on a fresh
# bind, false on:
#   - null router / null inventory (any of the two would make grants a
#     no-op or a crash; surface bad wiring at bind time)
#   - already bound to this same router (idempotent — re-binding would
#     double-subscribe and double-grant on every level-up)
# Re-binding to a *different* router transparently unbinds the old one
# so the orchestrator can reuse a router instance across runs without
# the caller having to remember the unbind step. Same shape as
# LocalXPRouter.bind.
func bind(router: LocalXPRouter, inventory: TokenInventory) -> bool:
	if router == null or inventory == null:
		return false
	if _router == router:
		return false
	if _router != null:
		unbind()
	_router = router
	_inventory = inventory
	_router.level_up.connect(_on_level_up)
	return true

# Disconnects from the bound router and clears state. Returns true on a
# successful unbind, false on no-op (not currently bound). Called by the
# orchestrator on session end so a stale subscriber doesn't keep
# granting tokens after teardown.
func unbind() -> bool:
	if _router == null:
		return false
	if _router.level_up.is_connected(_on_level_up):
		_router.level_up.disconnect(_on_level_up)
	_router = null
	_inventory = null
	return true

func is_bound() -> bool:
	return _router != null

func _on_level_up(old_level: int, new_level: int) -> void:
	if _inventory == null:
		return
	var earned := TokenGrantRules.tokens_for_level_up(old_level, new_level)
	if earned <= 0:
		return
	_inventory.grant(earned)
	granted_total += earned
