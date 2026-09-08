class_name StealAbility
extends EnemyAbility

# Steal archetype (PRD #518 / issue #572). Completes Trash Panda Tyrone: grabs
# a fistful of the player's gold on commit and then flees with it, so the
# player's counter is priority — corner him before he escapes, since the
# theft is only undone by killing him (Enemy.gd carries the amount forward;
# see AbilityLoadout's trash_panda_tyrone_loadout and Enemy._consume_ability_
# payload / Player._handle_enemy_killed for the recovery-on-kill path).
#
# Gold authority (the issue's "Unsure" resolution): CurrencyLedger, reached
# through GameState.currency_ledger, is the one balance a dungeon run tracks
# — it's what KillRewardRouter.gold_for_kill credits on every kill and what
# KittenSaveData.gold_balance persists at save time
# (KittenSaveData.gold_balance = currency_ledger.balance(...)). A CharacterData
# field would fork a second number nothing else reads; an in-run counter would
# fork a third. So this ability never touches a balance directly — it calls
# the caught object's own take_gold(amount), which on the real Player routes
# to that same ledger (see Player.take_gold) and on the test double is a
# plain int. Same shape either way: the ability trusts whatever authority the
# player object owns.
#
# The grab itself is a disc centered on the enemy (a lunge/snatch range, not
# a reach at the player like the tether), so "player standing in the zone at
# commit" is just distance-to-Tyrone. Fire-once is the base class's own
# commit edge (EnemyAbility._advance_zone) — this archetype doesn't track it
# again, per the issue's guidance.

var _cooldown: float
var _windup: float
var _commit: float
var _fade: float
var _radius: float
var _steal_amount: int

# Handoff to the Enemy node: the player caught by a successful theft, so the
# node can play the floating-text/VFX reaction. Same publish/consume shape as
# PullAbility.pending_pull_target. Null when no theft has landed since the
# last consume.
var pending_steal_target = null

# Cumulative gold this ability instance has actually taken across every
# firing of its life — the "carried" total the kill path returns (issue
# #572 acceptance: "the amount carried is exposed so the kill path can
# return it"). Only ever grows; Enemy.carried_gold mirrors it on consume.
var stolen_amount: int = 0

# Set true the instant a steal lands; never cleared, since once Tyrone has
# your gold he doesn't stop running until he's dead. desired_direction reads
# this to decide whether to flee at all.
var _fleeing: bool = false


func _init(
	cooldown_seconds: float = 7.0,
	windup_seconds: float = 0.5,
	commit_seconds: float = 0.2,
	fade_seconds: float = 0.3,
	grab_radius: float = 40.0,
	steal_amount_per_hit: int = 10
) -> void:
	_cooldown = cooldown_seconds
	_windup = windup_seconds
	_commit = commit_seconds
	_fade = fade_seconds
	_radius = grab_radius
	_steal_amount = steal_amount_per_hit


func cooldown() -> float:
	return _cooldown

func windup_duration() -> float:
	return _windup

func commit_duration() -> float:
	return _commit

func fade_duration() -> float:
	return _fade

func steal_amount() -> int:
	return _steal_amount

func is_fleeing() -> bool:
	return _fleeing


# Declines the firing (cooldown keeps running rather than resetting, per the
# base class's begin() contract) when there's no player to rob or the player
# is already broke — a steal against zero gold isn't a firing at all.
func _build_zone(enemy) -> DangerZoneShape:
	if enemy == null:
		return null
	var player = enemy.get("_player_ref")
	if player == null or not (player is Node2D) or not player.has_method("gold_balance"):
		return null
	if player.gold_balance() <= 0:
		return null
	var origin: Vector2 = enemy.global_position
	return DangerZoneShape.make_disc(origin, _radius, _windup, _commit, _fade)


func _on_commit(enemy, zone) -> void:
	var caught = resolve_hit(enemy, zone)
	if caught == null or not caught.has_method("take_gold"):
		return
	var taken: int = caught.take_gold(_steal_amount)
	if taken <= 0:
		return
	stolen_amount += taken
	_fleeing = true
	pending_steal_target = caught


# Flight direction (user stories 18/35): once a steal has landed, Tyrone
# flees rather than presses the fight — points straight away from the player,
# same "away when close, zero when there's no reason" shape as
# RetreatAndFireAbility.desired_direction's outer branch. Coincident
# positions fall back to a safe non-zero direction rather than NaN.
func desired_direction(enemy_pos: Vector2, player_pos: Vector2) -> Vector2:
	if not _fleeing:
		return Vector2.ZERO
	var away: Vector2 = enemy_pos - player_pos
	if away == Vector2.ZERO:
		return Vector2.RIGHT
	return away.normalized()
