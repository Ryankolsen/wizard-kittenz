class_name EnemyBehavior
extends RefCounted

# Per-kind tick hook (issue #157). The Enemy node calls `behavior.tick(delta, self)`
# each physics frame after the base state machine resolves; subclasses override
# `tick` to layer kind-specific behavior (dive bomb charge, wall bounce, water
# cone, etc.) on top of the shared chase/attack baseline. Default is a no-op so
# kinds without a registered behavior are safe and the wiring is the contract.
#
# Factory `for_kind` is exhaustive over EnemyData.EnemyKind so any kind — even
# one without a registered subclass yet — returns a non-null base instance.
# Per-kind subclasses land in follow-up issues (#161-#165).

func tick(_delta: float, _enemy) -> void:
	pass

# When a behavior wants to take exclusive control of motion this frame
# (e.g., Angry Pigeon's straight-line dive bomb that must ignore steering),
# it returns true and the Enemy node skips its state-machine match block,
# letting the behavior's tick write global_position / velocity unopposed.
# Default false so the standard chase/attack/idle baseline runs.
func is_overriding_motion() -> bool:
	return false

static func for_kind(kind: int) -> EnemyBehavior:
	match kind:
		EnemyData.EnemyKind.ANGRY_PIGEON:
			return AngryPigeonBehavior.new()
		EnemyData.EnemyKind.ROGUE_ROOMBA:
			return RogueRoombaBehavior.new()
	return EnemyBehavior.new()
