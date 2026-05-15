class_name CoopXPSubscriber
extends RefCounted

# Per-client XP routing subscriber. Subscribes to an XPBroadcaster's
# xp_awarded signal, filters by the local player_id, and applies the
# amount to a target PartyMember via XPSystem.award. Closes the
# "kill-by-anyone awards XP to all players" loop on the receiving end.
#
# Named "Subscriber" (vs. CoopRouter, which is its sibling for damage
# and revive) because this module has a stateful lifecycle: it
# constructs around a broadcaster, holds a signal connection, and
# requires unbind() on teardown. CoopRouter is a stateless static
# class — naming makes the distinction obvious.
#
# Why a separate module (vs. tallying inside XPBroadcaster, or as an
# inline lambda on Player.gd):
#   - XPBroadcaster's job is fan-out: it emits one xp_awarded per
#     registered player per kill. Every client receives every emission.
#     Filtering and stat application is a per-client concern that
#     doesn't belong in the broadcaster (would force solo callers to
#     pay for routing they don't need).
#   - As an inline subscriber on Player.gd, the filter rule + the
#     XPSystem.award call would be hidden inside the scene-tree node,
#     untestable in isolation. This subscriber is RefCounted + pure
#     data so a unit test pins the filter contract without booting a
#     scene.
#
# Note: applies XP to real_stats (use_real_level=true), so a level-10
# player scaled down to floor 3 still progresses toward their actual
# level-11 even though their effective_stats stays scaled. This is the
# rule from #18 PartyScaling AC#3 ("XP earned applies to the player's
# real level"); pinning it here keeps the rule explicit at the routing
# seam rather than hidden behind an XPSystem default.

# Emitted post-XPSystem.award when the local member's real_stats.level
# advanced. Lets a sibling subscriber (level-up VFX, milestone unlock
# detector) react to level-up edges without having to read the member
# level itself before/after each broadcast. Not emitted on flat XP gain
# (no level change). The (old, new) shape lets a multi-level dump
# report the full range so a subscriber can iterate intermediate
# levels in one emission.
signal level_up(old_level: int, new_level: int)

var local_player_id: String = ""
var local_member: PartyMember = null
var _broadcaster: XPBroadcaster = null
# Optional skill tree threaded through to XPSystem.award so a co-op
# level-up auto-unlocks newly-eligible nodes immediately, matching the
# solo path. Null preserves legacy behavior (XP applies, no unlock pass).
var _tree: SkillTree = null

func _init(broadcaster: XPBroadcaster = null, player_id: String = "", member: PartyMember = null, tree: SkillTree = null) -> void:
	if broadcaster != null:
		bind(broadcaster, player_id, member, tree)

# Connects to the broadcaster's xp_awarded signal. Returns true on a
# fresh bind, false on:
#   - null broadcaster / empty player_id / null member (any of the
#     three would make routing a no-op or a crash; surface the bad
#     wiring at bind time rather than silently dropping awards)
#   - already bound to this same broadcaster (idempotent — re-binding
#     would double-subscribe and double-apply XP on every event)
# Re-binding to a *different* broadcaster transparently unbinds the
# old one first so the subscriber can be reused across runs without
# the caller having to remember the unbind step.
func bind(broadcaster: XPBroadcaster, player_id: String, member: PartyMember, tree: SkillTree = null) -> bool:
	if broadcaster == null or player_id == "" or member == null:
		return false
	if _broadcaster == broadcaster:
		return false
	if _broadcaster != null:
		unbind()
	_broadcaster = broadcaster
	local_player_id = player_id
	local_member = member
	_tree = tree
	_broadcaster.xp_awarded.connect(_on_xp_awarded)
	return true

# Disconnects from the bound broadcaster and clears the routing state.
# Returns true on a successful unbind, false on no-op (not currently
# bound). Called by the orchestrator on session end so a stale
# subscriber doesn't keep applying XP after the session is torn down.
func unbind() -> bool:
	if _broadcaster == null:
		return false
	if _broadcaster.xp_awarded.is_connected(_on_xp_awarded):
		_broadcaster.xp_awarded.disconnect(_on_xp_awarded)
	_broadcaster = null
	local_player_id = ""
	local_member = null
	_tree = null
	return true

func is_bound() -> bool:
	return _broadcaster != null

func _on_xp_awarded(player_id: String, amount: int) -> void:
	# Filter: only the local player's emission lands on the local
	# member's stats. Every other party member's emission is handled
	# by their own client's subscriber.
	if player_id != local_player_id:
		return
	if local_member == null:
		return
	if local_member.real_stats == null:
		return
	# use_real_level=true: scaled effective_stats stay scaled; XP
	# advances real_stats only. (#18 AC#3)
	var old_level := local_member.real_stats.level
	XPSystem.award(local_member, amount, true, _tree)
	var new_level := local_member.real_stats.level
	if new_level > old_level:
		level_up.emit(old_level, new_level)
