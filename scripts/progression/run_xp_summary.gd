class_name RunXPSummary
extends RefCounted

# Per-run XP tally. Subscribes to an XPBroadcaster's xp_awarded signal
# and accumulates the amount under the recipient's player_id. The
# end-of-run summary screen (#17 AC #5) reads total_for(player_id) for
# each row and grand_total() for a "party total" header.
#
# Why a separate aggregator (vs. tallying inside XPBroadcaster):
#   - XPBroadcaster's job is fan-out. Re-tasking it as a tally would
#     leak per-run state into a per-session manager and force callers
#     who only want the broadcast (e.g. a UI floater that pops "+10 XP"
#     on every kill) to also pay for accumulator memory they don't read.
#   - The summary tally has its own lifetime: bound at run start, read
#     at run end, dropped when the next run begins. XPBroadcaster lives
#     for the whole session.
#   - Decoupling means a future "career stats" aggregator (lifetime XP)
#     can subscribe to the same signal without reading-the-other-stat-
#     out from the broadcaster.
#
# Bind via the constructor or bind() — both connect to xp_awarded.
# Idempotent: re-binding the same broadcaster doesn't double-count.
# unbind() disconnects so the caller can hard-stop accumulation (e.g.
# after the summary has been rendered, before the next run starts).

var _totals: Dictionary = {}  # player_id -> int

func _init(broadcaster: XPBroadcaster = null) -> void:
	if broadcaster != null:
		bind(broadcaster)

# Connects to the broadcaster's xp_awarded signal. Returns true on a
# fresh connection, false on null or already-connected (idempotent —
# can't double-subscribe and double-count).
func bind(broadcaster: XPBroadcaster) -> bool:
	if broadcaster == null:
		return false
	if broadcaster.xp_awarded.is_connected(_on_xp_awarded):
		return false
	broadcaster.xp_awarded.connect(_on_xp_awarded)
	return true

# Disconnects from the broadcaster. Returns true on a successful
# disconnect, false on null or not-connected. Lets the caller stop
# accumulation without throwing away the totals (read first, unbind,
# then clear() if the totals are also stale).
func unbind(broadcaster: XPBroadcaster) -> bool:
	if broadcaster == null:
		return false
	if not broadcaster.xp_awarded.is_connected(_on_xp_awarded):
		return false
	broadcaster.xp_awarded.disconnect(_on_xp_awarded)
	return true

func _on_xp_awarded(player_id: String, amount: int) -> void:
	# Defense-in-depth: XPBroadcaster.on_enemy_killed already filters
	# non-positive amounts, but a future hand-fired emit (e.g. test
	# harness) could route a 0 through, and we don't want it polluting
	# player_ids() with a zero-tally entry.
	if amount <= 0:
		return
	if player_id == "":
		return
	var current: int = int(_totals.get(player_id, 0))
	_totals[player_id] = current + amount

func total_for(player_id: String) -> int:
	return int(_totals.get(player_id, 0))

func grand_total() -> int:
	var sum := 0
	for v in _totals.values():
		sum += int(v)
	return sum

# Returns a snapshot of the player_ids currently in the tally. UI
# iterates this to render one row per player.
func player_ids() -> Array:
	return _totals.keys()

func player_count() -> int:
	return _totals.size()

# Returns a copy of the internal tally so the caller can serialize /
# render without exposing internal mutation. Same defensive shape as
# LobbyState.to_dict / KittenSaveData.to_dict.
func to_dict() -> Dictionary:
	return _totals.duplicate()

func clear() -> void:
	_totals.clear()
