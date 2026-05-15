class_name Spell
extends RefCounted

# A castable ability with a per-instance cooldown. EffectKind classifies the
# spell so a future SpellEffectResolver can dispatch on it (damage to one,
# area damage, or self-buff). For the tracer the kind + power tuple is enough
# to give each spell a distinct combat behavior.
enum EffectKind { DAMAGE, AREA, BUFF, HEAL, TAUNT }

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
# Optional self-damage cast cost (PRD #124, issue #129). When > 0 and a caster
# is supplied to cast(), the amount is deducted from caster.hp at cast time and
# the cast is blocked if it would leave the caster at <= 0 HP.
var hp_cost: int = 0

static func make(s_id: String, name: String, kind: int, power_val: int, cd: float = 1.0, hp_cost_val: int = 0) -> Spell:
	var s := Spell.new()
	s.id = s_id
	s.display_name = name
	s.effect_kind = kind
	s.power = power_val
	s.cooldown = cd
	s.base_cooldown = cd
	s.hp_cost = hp_cost_val
	return s

func is_ready() -> bool:
	return cooldown_remaining <= 0.0

# Tries to cast. If on cooldown, returns false and does not mutate state — so a
# re-press during cooldown is a no-op. On success, sets cooldown_remaining to
# the full cooldown and returns true. Caller is responsible for applying the
# spell's actual effect; this only governs gating.
#
# If hp_cost > 0 and a caster is supplied, deducts hp_cost from caster.hp at
# cast time. Blocked (returns false, no state mutation) if caster.hp <= hp_cost
# so a cast cannot kill or zero out the caster. With hp_cost == 0 or a null
# caster, behaves exactly as before.
func cast(caster = null) -> bool:
	if not is_ready():
		return false
	if hp_cost > 0 and caster != null and "hp" in caster:
		if caster.hp <= hp_cost:
			return false
		caster.hp -= hp_cost
	cooldown_remaining = cooldown
	return true

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - dt)
