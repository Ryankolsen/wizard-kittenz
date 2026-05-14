class_name Spell
extends RefCounted

# A castable ability with a per-instance cooldown. EffectKind classifies the
# spell so a future SpellEffectResolver can dispatch on it (damage to one,
# area damage, or self-buff). For the tracer the kind + power tuple is enough
# to give each spell a distinct combat behavior.
enum EffectKind { DAMAGE, AREA, BUFF }

var id: String = ""
var display_name: String = ""
var cooldown: float = 1.0
# Immutable base cooldown captured at make()-time. cooldown is the effective
# (post-magic_attack-scaling) value; base_cooldown is the source-of-truth for
# Player to re-derive each frame so magic_attack changes propagate without a
# separate hook (mirrors data.speed / data.dexterity rewriting).
var base_cooldown: float = 1.0
var effect_kind: int = EffectKind.DAMAGE
var power: int = 0
var cooldown_remaining: float = 0.0

static func make(s_id: String, name: String, kind: int, power_val: int, cd: float = 1.0) -> Spell:
	var s := Spell.new()
	s.id = s_id
	s.display_name = name
	s.effect_kind = kind
	s.power = power_val
	s.cooldown = cd
	s.base_cooldown = cd
	return s

func is_ready() -> bool:
	return cooldown_remaining <= 0.0

# Tries to cast. If on cooldown, returns false and does not mutate state — so a
# re-press during cooldown is a no-op. On success, sets cooldown_remaining to
# the full cooldown and returns true. Caller is responsible for applying the
# spell's actual effect; this only governs gating.
func cast() -> bool:
	if not is_ready():
		return false
	cooldown_remaining = cooldown
	return true

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - dt)
