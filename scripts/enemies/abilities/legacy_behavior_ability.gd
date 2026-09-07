class_name LegacyBehaviorAbility
extends EnemyAbility

# Placeholder archetype (PRD #518 / tracer slice #533) for kinds whose moves are
# still driven by their hand-written EnemyBehavior subclass. It produces no zone
# and commits nothing, so pumping it is free; its job is to keep the loadout
# table total over EnemyKind while issues #534-#545 convert each kind's real
# mechanics into archetypes. Delete it once the last kind is converted.

func cooldown() -> float:
	# Never fires: the pump asks wants_to_fire() and INF is never reached.
	return INF
