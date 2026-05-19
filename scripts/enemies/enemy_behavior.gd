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

static func for_kind(_kind: int) -> EnemyBehavior:
	return EnemyBehavior.new()
