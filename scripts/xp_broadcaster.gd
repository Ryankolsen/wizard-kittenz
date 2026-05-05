class_name XPBroadcaster
extends RefCounted

# Co-op XP fan-out: a kill by any player awards XP to every registered
# party member, not just the killer. Caller registers each player_id at
# session start; on_enemy_killed emits xp_awarded once per registered id
# with the same amount, regardless of who got the killing blow.
#
# Matches user story 22 ("a kill by any player awards XP to all
# players"). killer_id is plumbed for future telemetry / "killing blow"
# UI flag, but the data contract is uniform: same amount for every
# party member. Per-player application is the caller's job — XPSystem
# .award routes the per-id amount to the right CharacterData on each
# client.
signal xp_awarded(player_id: String, amount: int)

var _player_ids: Array[String] = []

# Registers a party member to receive XP broadcasts. Returns true on
# success, false on duplicate / empty id (idempotent — re-registering
# the same id is a no-op rather than an error).
func register_player(player_id: String) -> bool:
	if player_id == "":
		return false
	if _player_ids.has(player_id):
		return false
	_player_ids.append(player_id)
	return true

func unregister_player(player_id: String) -> bool:
	var idx := _player_ids.find(player_id)
	if idx < 0:
		return false
	_player_ids.remove_at(idx)
	return true

func registered_players() -> Array[String]:
	return _player_ids.duplicate()

func player_count() -> int:
	return _player_ids.size()

func has_player(player_id: String) -> bool:
	return _player_ids.has(player_id)

# Broadcasts an XP award to every registered player. Non-positive
# amounts are a no-op (same shape as ProgressionSystem.add_xp's
# negative-amount guard) so a future debuff that subtracts XP can't
# silently drive negative emissions through the fan-out.
func on_enemy_killed(xp_value: int, killer_id: String = "") -> void:
	if xp_value <= 0:
		return
	for pid in _player_ids:
		xp_awarded.emit(pid, xp_value)

func clear() -> void:
	_player_ids.clear()
