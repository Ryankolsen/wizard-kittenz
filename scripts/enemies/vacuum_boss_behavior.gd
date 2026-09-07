class_name VacuumBossBehavior
extends EnemyBehavior

# Floor-1 boss behavior (PRD #518 / tracer slice #533). It declares no bespoke
# logic of its own — everything the Vacuum does comes from the archetypes in its
# loadout, pumped generically by the Enemy node. That is the shape every later
# boss slice (#534-#545) is meant to copy: a behavior is a name plus a loadout.
#
# It exists as a distinct class (rather than the base) so BossRoster's reuse of
# EnemyKind.ROGUE_ROOMBA for the Vacuum does not drag the standard roomba's
# bounce/trail logic onto the boss.

func _init() -> void:
	abilities = AbilityLoadout.vacuum_loadout()
