class_name PotionDefinition
extends RefCounted

# Pure-data record for one potion type (PRD #358 / slice 1). The catalog is the
# single source of truth; effect kind, magnitude, and duration are read by the
# PotionEffectResolver in slice 3. icon is optional (defaults to null) so the
# catalog can be seeded long before sprite assets exist — slice 7/8 hooks the
# texture into the belt HUD when art lands.

enum EffectKind { HEAL_PERCENT, MANA_PERCENT, SHIELD }

var id: String = ""
var display_name: String = ""
var description: String = ""
var effect_kind: int = EffectKind.HEAL_PERCENT
# Magnitude semantics depend on effect_kind: HEAL/MANA_PERCENT use it as a
# percent of max (0..100); SHIELD uses it as a flat absorb amount.
var magnitude: int = 0
# Seconds the effect lasts. Instant effects use 0.
var duration: float = 0.0
# Category id for the shop tab grouping in slice 5 — also drives the row color
# language in the future Items tab UI (slice 9).
var category: String = ""
var icon: Texture2D = null

static func make(p_id: String, p_name: String, p_desc: String, p_kind: int, p_magnitude: int, p_duration: float, p_category: String, p_icon: Texture2D = null) -> PotionDefinition:
	var d := PotionDefinition.new()
	d.id = p_id
	d.display_name = p_name
	d.description = p_desc
	d.effect_kind = p_kind
	d.magnitude = p_magnitude
	d.duration = p_duration
	d.category = p_category
	d.icon = p_icon
	return d
