class_name EnrageAbility
extends EnemyAbility

# Enrage archetype (PRD #518 / issue #575). Deliberately restricted to exactly
# two bosses across the whole roster -- Last Call Larry and DJ Dubstep -- per
# the PRD's rejection of a universal rage state (see
# test_enemy_behavior.gd's roster-constraint test): the point is that enrage
# stays a distinctive moment, not a thing every fight does.
#
# A one-way, one-shot state change rather than an attack: once the enemy's HP
# first falls to or below its configured threshold fraction, its move speed
# and damage spike by their configured factors exactly once, and it never
# re-fires even if HP recovers above the threshold and falls again. Follows
# RogueRoombaBehavior's berserk shape (BERSERK_HP_FRACTION / SPEED_MULTIPLIER
# / a monotonic one-shot entry count) but as a composable archetype instead of
# a per-kind branch, so a boss can carry it through AbilityLoadout instead of
# a bespoke behavior subclass.
#
# Deliberately produces no danger zone -- there's nothing to telegraph, the
# flip is instantaneous -- so the work happens on `tick`, not on a wind-up/
# commit edge the way every other archetype's payload does. `wants_to_fire`
# is pinned to false: this ability never enters the pump's begin()/
# is_active() zone machinery. That matters because the generic pump's "one
# telegraph at a time" selection loop (Enemy._pump_abilities) calls begin()
# on the first ability that answers wants_to_fire() and returns for the
# frame; if enrage inherited the cooldown-based default it would answer true
# as soon as its aggro-gated cooldown elapsed and then *stay* true forever
# (nothing ever resets the cooldown, since `_build_zone` always declines),
# winning that selection every single frame and starving a sibling ability
# --  Larry's actual zone-denial archetype -- of ever reaching begin() at
# all. Answering false keeps this a tick-only participant in the generic
# pump, which is enough: `EnemyAbility.tick` is still called on it every
# frame with no per-kind branch in enemy.gd.
#
# Investigated separately whether the base class's "a null `_build_zone`
# return abandons the firing" path (EnemyAbility.begin) needed a change for
# this archetype to work: it does not. Nothing here ever reaches begin()
# through the pump (wants_to_fire() is false), and a defensive direct call to
# begin() is harmless -- it returns before touching any state this ability's
# tick-driven bookkeeping relies on, so there is nothing to "abandon."

var _hp_fraction: float
var _speed_multiplier: float
var _damage_multiplier: float

# One-shot flag, mirroring RogueRoombaBehavior.is_berserk.
var has_enraged: bool = false
# Monotonic counter, mirroring RogueRoombaBehavior.berserk_entry_count:
# incremented exactly once when the threshold is first crossed, and never
# again even if HP climbs back above the threshold and falls a second time.
var enrage_entry_count: int = 0


func _init(
	hp_fraction: float = 0.3,
	speed_multiplier: float = 1.5,
	damage_multiplier: float = 1.5
) -> void:
	_hp_fraction = hp_fraction
	_speed_multiplier = speed_multiplier
	_damage_multiplier = damage_multiplier


func hp_fraction() -> float:
	return _hp_fraction

func speed_multiplier() -> float:
	return _speed_multiplier

func damage_multiplier() -> float:
	return _damage_multiplier

# See the class comment: this archetype never fires through the zone pump.
func wants_to_fire() -> bool:
	return false

# Enrage has nothing to telegraph or commit; declining unconditionally keeps
# begin() a safe no-op on the rare chance anything calls it directly.
func _build_zone(_enemy) -> DangerZoneShape:
	return null


func tick(_delta: float, enemy) -> void:
	_check_enrage(enemy)


func _check_enrage(enemy) -> void:
	if has_enraged or enemy == null:
		return
	# Same DEAD/IDLE sink RogueRoombaBehavior applies to berserk: a dead or
	# never-engaged enemy doesn't enrage.
	if not EnemyBehavior.is_aggroed(enemy):
		return
	var d = enemy.get("data")
	if d == null:
		return
	var max_hp_val = d.get("max_hp")
	var hp_val = d.get("hp")
	if max_hp_val == null or hp_val == null or float(max_hp_val) <= 0.0:
		return
	# Inclusive threshold, same as RogueRoombaBehavior's berserk (`<=
	# BERSERK_HP_FRACTION`): HP exactly at the line already counts as low
	# enough to enrage.
	if float(hp_val) / float(max_hp_val) > _hp_fraction:
		return
	has_enraged = true
	enrage_entry_count += 1
	var speed_val = enemy.get("move_speed")
	if speed_val != null:
		enemy.set("move_speed", float(speed_val) * _speed_multiplier)
	var attack_val = d.get("attack")
	if attack_val != null:
		d.set("attack", attack_val * _damage_multiplier)
