class_name PetrifyEffect
extends PowerUpEffect

# Locks player movement for `duration` seconds while leaving attacks, spells
# and potion use fully available (PRD #518 / issue #536). Landed by Sir
# Pickleton's ambush archetype. Same tick-based shape as WetEffect /
# SlownessEffect / ConfusionEffect; unlike the speed debuffs this one doesn't
# touch `speed` at all — it pushes a counter on CharacterData
# (push_petrify/pop_petrify, mirroring ConfusionEffect's push/pop pair) and
# Player._physics_process reads is_petrified() to zero movement input. Attack,
# spell and potion systems (AttackController, Spell, PotionBelt) never
# reference this flag, so they stay available by construction rather than by
# an explicit allow-list.

const TYPE := "petrify"
# PRD #518 "Petrify": duration ~1.5-2s.
const DEFAULT_DURATION := 1.75

func _init(duration_seconds: float = DEFAULT_DURATION) -> void:
	type = TYPE
	duration = duration_seconds
	remaining = duration_seconds

func _on_apply(target) -> void:
	target.push_petrify()

func _on_remove(target) -> void:
	target.pop_petrify()
