class_name AmbushAbility
extends EnemyAbility

# Ambush / petrify archetype (PRD #518 / issue #536). Wraps AmbushTracker's
# pure blind-arc/charge accounting: charge accrues only while this enemy sits
# in the player's blind arc, drains the instant the player faces it, and a
# firing only begins once the tracker reports the scare actually landed. The
# player's counter is attention, not movement.
#
# Composed alongside TelegraphedChargeAbility in AbilityLoadout.pickleton_loadout.
# If the player turns to face mid wind-up, the tracker's own charge starts
# draining and `wants_to_fire` drops back to false with no cooldown started —
# that's what "failing to land the scare forces the telegraphed charge" means
# in practice: the shared ability pump's "one telegraph at a time, fire
# whichever ability wants it" loop (Enemy._pump_abilities) simply lets the
# charge archetype take the next slot. No explicit fallback wiring needed.
#
# The zone is deliberately short — a brief wind-up escalating straight to
# commit — so the telegraph reads as the PRD's "quiet cue escalating to a
# full danger zone only for the final ~0.4s" rather than a long, readable
# wind-up like the other archetypes.

var tracker: AmbushTracker = AmbushTracker.new()
# Handoff to the Enemy node, consumed the same way pending_hit_target /
# pending_pull_target are (see Enemy._consume_ability_payload).
var pending_petrify_target = null

var _windup: float
var _commit: float
var _fade: float
var _range: float
var _petrify_duration: float
var _scare_ready: bool = false


func _init(
	windup_seconds: float = 0.4,
	commit_seconds: float = 0.2,
	fade_seconds: float = 0.3,
	scare_range: float = 40.0,
	petrify_duration: float = 1.75
) -> void:
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_range = scare_range
	_petrify_duration = petrify_duration


# No flat cooldown clock — firing is gated entirely by the tracker's charge
# and its own post-scare cooldown.
func cooldown() -> float:
	return 0.0

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade

func petrify_duration() -> float:
	return _petrify_duration


func tick(delta: float, enemy) -> void:
	if is_active():
		_advance_zone(delta, enemy)
		return
	if not EnemyBehavior.is_aggroed(enemy):
		_scare_ready = false
		return
	var player = _player_of(enemy)
	var enemy_pos = enemy.global_position if enemy != null else null
	if player == null or enemy_pos == null:
		_scare_ready = false
		return
	var player_pos: Vector2 = player.global_position
	var facing := _facing_of(player)
	tracker.tick(delta, player_pos, facing, enemy_pos)
	_scare_ready = tracker.can_scare(player_pos, facing, enemy_pos)


func wants_to_fire() -> bool:
	return not is_active() and _scare_ready


func _build_zone(enemy) -> DangerZoneShape:
	var target = target_position(enemy)
	if target == null:
		return null
	var origin: Vector2 = enemy.global_position
	var span: Vector2 = (target as Vector2) - origin
	var length: float = span.length()
	if length <= 0.0:
		return null
	return DangerZoneShape.make_lane(origin, span, length, _range, _windup, _commit, _fade)


func _on_commit(enemy, zone) -> void:
	var caught = resolve_hit(enemy, zone)
	if caught == null:
		return
	var player = _player_of(enemy)
	if player == null or player != caught:
		return
	var enemy_pos = enemy.global_position if enemy != null else null
	var player_pos: Vector2 = player.global_position
	var facing := _facing_of(player)
	if not tracker.can_scare(player_pos, facing, enemy_pos):
		# The player turned to face it mid wind-up — the scare fails to land.
		# No cooldown starts; the tracker's charge is already draining from
		# the facing check, which is what forces the fallback described above.
		return
	tracker.trigger_scare()
	pending_petrify_target = caught


func _player_of(enemy):
	if enemy == null:
		return null
	var p = enemy.get("_player_ref")
	if p == null or not (p is Node2D):
		return null
	return p


func _facing_of(player) -> Vector2:
	if player == null:
		return Vector2.ZERO
	var data = player.get("data")
	if data != null and "facing" in data:
		return data.facing
	return Vector2.ZERO
